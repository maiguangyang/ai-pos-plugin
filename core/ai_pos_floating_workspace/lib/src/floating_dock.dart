import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'floating_motion_policy.dart';
import 'floating_snapshot.dart';

abstract interface class _FloatingDockDelegate {
  double get revealProgress;
  Rect? cardGlobalRect(Object id);
  Future<void> collapse();
  void setApplicationActive(bool active);
}

final class FloatingDockController extends ChangeNotifier {
  _FloatingDockDelegate? _delegate;
  double _revealProgress = 0;
  bool _applicationActive = true;

  double get revealProgress => _revealProgress;
  bool get isExpanded => _revealProgress > 0.000001;

  Rect? cardGlobalRect(Object id) => _delegate?.cardGlobalRect(id);

  Future<void> collapse() async => _delegate?.collapse();

  void setApplicationActive(bool active) {
    _applicationActive = active;
    _delegate?.setApplicationActive(active);
  }

  void _attach(_FloatingDockDelegate delegate) {
    final current = _delegate;
    if (current != null && !identical(current, delegate)) {
      throw StateError('The floating dock controller is already attached.');
    }
    _delegate = delegate;
    delegate.setApplicationActive(_applicationActive);
    _update(delegate.revealProgress);
  }

  void _detach(_FloatingDockDelegate delegate) {
    if (identical(_delegate, delegate)) {
      _delegate = null;
      _revealProgress = 0;
    }
  }

  void _update(double value) {
    if (_revealProgress == value) {
      return;
    }
    final wasExpanded = isExpanded;
    _revealProgress = value;
    if (wasExpanded != isExpanded) {
      notifyListeners();
    }
  }
}

@immutable
final class FloatingDockCard {
  const FloatingDockCard({
    required this.id,
    required this.title,
    required this.snapshot,
    required this.onRestore,
    required this.onClose,
  });

  final Object id;
  final String title;
  final FloatingSnapshot snapshot;
  final ValueChanged<Rect> onRestore;
  final VoidCallback onClose;
}

final class FloatingDock extends StatefulWidget {
  FloatingDock({
    super.key,
    required this.cards,
    this.revealExtent = 320,
    this.initialDockVerticalFraction = 0.5,
    this.onDockVerticalFractionChanged,
    this.dockSemanticLabel = 'Open floating windows',
    this.cardOpenSemanticLabel = 'Open',
    this.cardCloseSemanticLabel = 'Close',
    this.controller,
    this.handleSystemBack = true,
    FloatingMotionPolicy? motionPolicy,
  }) : motionPolicy = motionPolicy ?? FloatingMotionPolicy(),
       assert(revealExtent > 0),
       assert(
         initialDockVerticalFraction >= 0 && initialDockVerticalFraction <= 1,
       );

  static const dockHitTargetKey = Key('ai-pos-floating-dock-hit-target');
  static const scrimKey = Key('ai-pos-floating-scrim');

  static Key cardKey(Object id) => ValueKey<String>('ai-pos-floating-card-$id');
  static Key cardCloseKey(Object id) =>
      ValueKey<String>('ai-pos-floating-card-close-$id');
  static Key cardOpacityKey(Object id) =>
      ValueKey<String>('ai-pos-floating-card-opacity-$id');
  static Key cardTransformKey(Object id) =>
      ValueKey<String>('ai-pos-floating-card-transform-$id');
  static Key cardRepaintBoundaryKey(Object id) =>
      ValueKey<String>('ai-pos-floating-card-repaint-$id');

  final List<FloatingDockCard> cards;
  final double revealExtent;
  final double initialDockVerticalFraction;
  final ValueChanged<double>? onDockVerticalFractionChanged;
  final String dockSemanticLabel;
  final String cardOpenSemanticLabel;
  final String cardCloseSemanticLabel;
  final FloatingDockController? controller;
  final bool handleSystemBack;
  final FloatingMotionPolicy motionPolicy;

  @override
  State<FloatingDock> createState() => _FloatingDockState();
}

final class _FloatingDockState extends State<FloatingDock>
    with SingleTickerProviderStateMixin
    implements _FloatingDockDelegate {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: 1,
  );
  late final ValueNotifier<bool> _dragging = ValueNotifier<bool>(false);
  late final ValueNotifier<double> _trackOffset = ValueNotifier<double>(0);
  final Map<Object, GlobalKey> _cardGeometryKeys = <Object, GlobalKey>{};
  bool _applicationActive = true;
  bool _panningTrack = false;
  double _dragOriginX = 0;
  double _dragOriginProgress = 0;
  double _dragOriginTrackOffset = 0;
  double _trackMinOffset = 0;
  double _trackMaxOffset = 0;
  double? _dockVerticalFraction;

  bool get _disableAnimations => MediaQuery.disableAnimationsOf(context);
  double get _resolvedDockVerticalFraction =>
      _dockVerticalFraction ??= widget.initialDockVerticalFraction;

  @override
  void initState() {
    super.initState();
    _dockVerticalFraction = widget.initialDockVerticalFraction;
    _reveal.addListener(_notifyRevealProgress);
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant FloatingDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (widget.cards.isEmpty) {
      _reveal.value = 0;
      _trackOffset.value = 0;
    }
    final currentIds = widget.cards.map((card) => card.id).toSet();
    _cardGeometryKeys.removeWhere((id, _) => !currentIds.contains(id));
  }

  void _notifyRevealProgress() => widget.controller?._update(_reveal.value);

  @override
  double get revealProgress => _reveal.value;

  @override
  Rect? cardGlobalRect(Object id) {
    final context = _cardGeometryKeys[id]?.currentContext;
    final box = context?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return null;
    }
    return Rect.fromPoints(
      box.localToGlobal(Offset.zero),
      box.localToGlobal(box.size.bottomRight(Offset.zero)),
    );
  }

  @override
  Future<void> collapse() => _settle(0, velocityX: 0);

  @override
  void setApplicationActive(bool active) {
    if (_applicationActive == active) {
      return;
    }
    _applicationActive = active;
    if (!active) {
      final target = _reveal.value < 0.5 ? 0.0 : 1.0;
      _reveal.stop(canceled: true);
      _reveal.value = target;
      if (target == 0) {
        _trackOffset.value = 0;
      }
      _dragging.value = false;
    }
  }

  void _toggle() {
    if (_applicationActive) {
      unawaited(_settle(_reveal.value < 0.5 ? 1 : 0, velocityX: 0));
    }
  }

  void _onDragStart(DragStartDetails details) {
    if (!_applicationActive) {
      return;
    }
    _panningTrack = false;
    _reveal.stop();
    _dragOriginX = details.globalPosition.dx;
    _dragOriginProgress = _reveal.value;
    _dragging.value = true;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_applicationActive) {
      return;
    }
    final dragDistance = details.globalPosition.dx - _dragOriginX;
    _reveal.value = (_dragOriginProgress - dragDistance / widget.revealExtent)
        .clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_applicationActive) {
      return;
    }
    _dragging.value = false;
    final velocityX = details.velocity.pixelsPerSecond.dx;
    final target = widget.motionPolicy.targetForRelease(
      progress: _reveal.value,
      velocityX: velocityX,
    );
    unawaited(_settle(target, velocityX: velocityX));
  }

  void _onDragCancel() {
    if (!_applicationActive || !_dragging.value) {
      return;
    }
    _dragging.value = false;
    unawaited(_settle(0, velocityX: 0));
  }

  void _onCardDragStart(DragStartDetails details) {
    if (!_applicationActive) {
      return;
    }
    if (_reveal.value >= 1 - 0.000001 && _trackMinOffset < _trackMaxOffset) {
      _panningTrack = true;
      _dragOriginX = details.globalPosition.dx;
      _dragOriginTrackOffset = _trackOffset.value.clamp(
        _trackMinOffset,
        _trackMaxOffset,
      );
      _dragging.value = true;
      return;
    }
    _onDragStart(details);
  }

  void _onCardDragUpdate(DragUpdateDetails details) {
    if (_panningTrack) {
      final dragDistance = details.globalPosition.dx - _dragOriginX;
      _trackOffset.value = (_dragOriginTrackOffset + dragDistance).clamp(
        _trackMinOffset,
        _trackMaxOffset,
      );
      return;
    }
    _onDragUpdate(details);
  }

  void _onCardDragEnd(DragEndDetails details) {
    if (_panningTrack) {
      _panningTrack = false;
      _dragging.value = false;
      return;
    }
    _onDragEnd(details);
  }

  void _onCardDragCancel() {
    if (_panningTrack) {
      _panningTrack = false;
      _dragging.value = false;
      return;
    }
    _onDragCancel();
  }

  void _onDockVerticalDragUpdate(
    DragUpdateDetails details,
    double availableHeight,
  ) {
    if (!_applicationActive) {
      return;
    }
    const dockHeight = 96.0;
    final effectiveDockHeight = math.min(dockHeight, availableHeight);
    final halfDockHeight = effectiveDockHeight / 2;
    final currentCenter = _resolvedDockVerticalFraction * availableHeight;
    final nextCenter = (currentCenter + details.delta.dy).clamp(
      halfDockHeight,
      availableHeight - halfDockHeight,
    );
    final nextFraction = nextCenter / availableHeight;
    setState(() => _dockVerticalFraction = nextFraction);
    widget.onDockVerticalFractionChanged?.call(nextFraction);
  }

  Future<void> _settle(double target, {required double velocityX}) async {
    final duration = _disableAnimations
        ? const Duration(milliseconds: 120)
        : widget.motionPolicy.settleDuration(
            progress: _reveal.value,
            target: target,
            velocityX: velocityX,
          );
    try {
      await _reveal
          .animateTo(target, duration: duration, curve: Curves.easeOutCubic)
          .orCancel;
      if (target == 0) {
        _trackOffset.value = 0;
      }
    } on TickerCanceled {
      // Disposal or a new gesture superseded this settle animation.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _reveal,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          _buildScrim(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.hardEdge,
                children: [
                  ..._buildCards(constraints),
                  _buildDock(constraints),
                ],
              ),
            ),
          ),
        ],
      ),
      builder: (context, child) {
        final progress = _reveal.value;
        return PopScope<void>(
          canPop: !widget.handleSystemBack || progress == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (widget.handleSystemBack && !didPop) {
              unawaited(_settle(0, velocityX: 0));
            }
          },
          child: child!,
        );
      },
    );
  }

  Widget _buildScrim() {
    return AnimatedBuilder(
      animation: _reveal,
      builder: (context, _) {
        final progress = _reveal.value;
        if (progress == 0) {
          return const SizedBox.shrink();
        }
        return GestureDetector(
          key: FloatingDock.scrimKey,
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: () => unawaited(_settle(0, velocityX: 0)),
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: _onDragCancel,
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.36 * progress),
          ),
        );
      },
    );
  }

  Iterable<Widget> _buildCards(BoxConstraints constraints) sync* {
    final count = widget.cards.length;
    if (count == 0) {
      return;
    }
    const cardGap = 12.0;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final cardWidth = (width * 0.3).clamp(112.0, 168.0);
    final cardHeight = math.min(height * 0.48, cardWidth * 1.55);
    final trackWidth = cardWidth * count + cardGap * (count - 1);
    final trackLeft = (width - trackWidth) / 2;
    final trackTop = math.max(0.0, (height - cardHeight) / 2);
    const trackEdgeInset = 8.0;
    _trackMinOffset = math.min(
      0.0,
      width - trackEdgeInset - (trackLeft + trackWidth),
    );
    _trackMaxOffset = math.max(0.0, trackEdgeInset - trackLeft);
    final dockCenterY = (_resolvedDockVerticalFraction * height).clamp(
      48.0,
      height - 48.0,
    );
    final dockRect = Rect.fromLTWH(width - 12, dockCenterY - 44, 56, 88);
    for (var index = 0; index < count; index += 1) {
      final card = widget.cards[index];
      final visualIndex = count - 1 - index;
      final finalRect = Rect.fromLTWH(
        trackLeft + (cardWidth + cardGap) * visualIndex,
        trackTop,
        cardWidth,
        cardHeight,
      );
      yield Positioned.fromRect(
        rect: finalRect,
        child: _FloatingCardProjection(
          geometryKey: _cardGeometryKeys.putIfAbsent(card.id, GlobalKey.new),
          card: card,
          reveal: _reveal,
          dragging: _dragging,
          trackOffset: _trackOffset,
          trackMinOffset: _trackMinOffset,
          trackMaxOffset: _trackMaxOffset,
          dockRect: dockRect,
          expandedRect: finalRect,
          openSemanticLabel: widget.cardOpenSemanticLabel,
          closeSemanticLabel: widget.cardCloseSemanticLabel,
          onHorizontalDragStart: _onCardDragStart,
          onHorizontalDragUpdate: _onCardDragUpdate,
          onHorizontalDragEnd: _onCardDragEnd,
          onHorizontalDragCancel: _onCardDragCancel,
        ),
      );
    }
  }

  Widget _buildDock(BoxConstraints constraints) {
    const dockWidth = 56.0;
    const dockHeight = 96.0;
    final effectiveDockHeight = math.min(dockHeight, constraints.maxHeight);
    final dockTop =
        (_resolvedDockVerticalFraction * constraints.maxHeight -
                effectiveDockHeight / 2)
            .clamp(0.0, constraints.maxHeight - effectiveDockHeight);
    return Positioned(
      top: dockTop,
      right: 0,
      child: AnimatedBuilder(
        animation: _reveal,
        child: Container(
          width: 22,
          height: 88,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.inverseSurface.withValues(alpha: 0.72),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(11),
            ),
          ),
          child: Icon(
            Icons.more_vert_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.onInverseSurface,
          ),
        ),
        builder: (context, child) {
          final progress = _reveal.value;
          return Semantics(
            label: widget.dockSemanticLabel,
            button: true,
            expanded: progress > 0,
            child: GestureDetector(
              key: FloatingDock.dockHitTargetKey,
              behavior: HitTestBehavior.translucent,
              dragStartBehavior: DragStartBehavior.down,
              onTap: _toggle,
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              onHorizontalDragCancel: _onDragCancel,
              onVerticalDragUpdate: progress == 0
                  ? (details) => _onDockVerticalDragUpdate(
                      details,
                      constraints.maxHeight,
                    )
                  : null,
              child: SizedBox(
                width: dockWidth,
                height: effectiveDockHeight,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Opacity(opacity: 1 - progress, child: child),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _reveal.removeListener(_notifyRevealProgress);
    _reveal.dispose();
    _dragging.dispose();
    _trackOffset.dispose();
    super.dispose();
  }
}

final class _FloatingCardProjection extends StatelessWidget {
  const _FloatingCardProjection({
    required this.geometryKey,
    required this.card,
    required this.reveal,
    required this.dragging,
    required this.trackOffset,
    required this.trackMinOffset,
    required this.trackMaxOffset,
    required this.dockRect,
    required this.expandedRect,
    required this.openSemanticLabel,
    required this.closeSemanticLabel,
    required this.onHorizontalDragStart,
    required this.onHorizontalDragUpdate,
    required this.onHorizontalDragEnd,
    required this.onHorizontalDragCancel,
  });

  final GlobalKey geometryKey;
  final FloatingDockCard card;
  final Animation<double> reveal;
  final ValueNotifier<bool> dragging;
  final ValueNotifier<double> trackOffset;
  final double trackMinOffset;
  final double trackMaxOffset;
  final Rect dockRect;
  final Rect expandedRect;
  final String openSemanticLabel;
  final String closeSemanticLabel;
  final GestureDragStartCallback onHorizontalDragStart;
  final GestureDragUpdateCallback onHorizontalDragUpdate;
  final GestureDragEndCallback onHorizontalDragEnd;
  final GestureDragCancelCallback onHorizontalDragCancel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([reveal, dragging, trackOffset]),
      child: RepaintBoundary(
        key: FloatingDock.cardRepaintBoundaryKey(card.id),
        child: _FloatingCardSurface(
          card: card,
          openSemanticLabel: openSemanticLabel,
          closeSemanticLabel: closeSemanticLabel,
        ),
      ),
      builder: (context, child) {
        final cardProgress = _normalizedUnit(reveal.value);
        final resolvedTrackOffset = trackOffset.value.clamp(
          trackMinOffset,
          trackMaxOffset,
        );
        final resolvedExpandedRect = expandedRect.shift(
          Offset(resolvedTrackOffset, 0),
        );
        final currentRect = Rect.lerp(
          dockRect,
          resolvedExpandedRect,
          cardProgress,
        )!;
        final transform = Matrix4.identity()
          ..setEntry(0, 0, currentRect.width / expandedRect.width)
          ..setEntry(1, 1, currentRect.height / expandedRect.height)
          ..setEntry(0, 3, currentRect.left - expandedRect.left)
          ..setEntry(1, 3, currentRect.top - expandedRect.top);
        return Transform(
          alignment: Alignment.topLeft,
          transform: transform,
          child: KeyedSubtree(
            key: geometryKey,
            child: GestureDetector(
              key: FloatingDock.cardTransformKey(card.id),
              behavior: HitTestBehavior.translucent,
              dragStartBehavior: DragStartBehavior.down,
              onHorizontalDragStart: onHorizontalDragStart,
              onHorizontalDragUpdate: onHorizontalDragUpdate,
              onHorizontalDragEnd: onHorizontalDragEnd,
              onHorizontalDragCancel: onHorizontalDragCancel,
              child: Opacity(
                key: FloatingDock.cardOpacityKey(card.id),
                opacity: cardProgress,
                child: IgnorePointer(
                  ignoring: cardProgress < 1 || dragging.value,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

double _normalizedUnit(double value) {
  const endpointTolerance = 0.000001;
  if (value <= endpointTolerance) {
    return 0;
  }
  if (value >= 1 - endpointTolerance) {
    return 1;
  }
  return value.clamp(0.0, 1.0);
}

final class _FloatingCardSurface extends StatelessWidget {
  const _FloatingCardSurface({
    required this.card,
    required this.openSemanticLabel,
    required this.closeSemanticLabel,
  });

  final FloatingDockCard card;
  final String openSemanticLabel;
  final String closeSemanticLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: FloatingDock.cardKey(card.id),
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        label: '${openSemanticLabel.trim()} ${card.title}',
        button: true,
        container: true,
        explicitChildNodes: true,
        child: InkWell(
          onTap: () {
            final box = context.findRenderObject();
            if (box is RenderBox && box.hasSize) {
              card.onRestore(box.localToGlobal(Offset.zero) & box.size);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              card.snapshot.build(fit: BoxFit.cover),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.68),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 22, 12, 10),
                      child: ExcludeSemantics(
                        child: Text(
                          card.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: Semantics(
                  label: '${closeSemanticLabel.trim()} ${card.title}',
                  button: true,
                  child: SizedBox(
                    key: FloatingDock.cardCloseKey(card.id),
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.46),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: card.onClose,
                          child: const SizedBox(
                            width: 26,
                            height: 26,
                            child: Icon(
                              Icons.close_rounded,
                              size: 17,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
