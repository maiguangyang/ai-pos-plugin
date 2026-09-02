import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'plugin_motion_policy.dart';
import 'plugin_snapshot.dart';

abstract interface class _AiPosPluginFloatingOverlayDelegate {
  double get revealProgress;

  Future<void> collapse();

  void setApplicationActive(bool active);
}

/// Host-owned handle for coordinating the floating overlay with system back.
final class AiPosPluginFloatingOverlayController extends ChangeNotifier {
  _AiPosPluginFloatingOverlayDelegate? _delegate;
  double _revealProgress = 0;
  bool _applicationActive = true;

  double get revealProgress => _revealProgress;
  bool get isExpanded => _revealProgress > 0.000001;

  Future<void> collapse() async {
    await _delegate?.collapse();
  }

  /// Disables stale gestures and settles the reveal while the app is inactive.
  void setApplicationActive(bool active) {
    _applicationActive = active;
    _delegate?.setApplicationActive(active);
  }

  void _attach(_AiPosPluginFloatingOverlayDelegate delegate) {
    final current = _delegate;
    if (current != null && !identical(current, delegate)) {
      throw StateError('The floating overlay controller is already attached.');
    }
    _delegate = delegate;
    delegate.setApplicationActive(_applicationActive);
    _update(delegate.revealProgress);
  }

  void _detach(_AiPosPluginFloatingOverlayDelegate delegate) {
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
final class AiPosPluginFloatingCard {
  const AiPosPluginFloatingCard({
    required this.pluginId,
    required this.pluginName,
    required this.snapshot,
    required this.onRestore,
    required this.onClose,
  });

  final String pluginId;
  final String pluginName;
  final AiPosPluginSnapshot snapshot;
  final ValueChanged<Rect> onRestore;
  final VoidCallback onClose;
}

/// Host-only right-edge dock and continuous floating-card reveal layer.
final class AiPosPluginFloatingOverlay extends StatefulWidget {
  AiPosPluginFloatingOverlay({
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
    AiPosPluginMotionPolicy? motionPolicy,
  }) : motionPolicy = motionPolicy ?? AiPosPluginMotionPolicy(),
       assert(revealExtent > 0),
       assert(
         initialDockVerticalFraction >= 0 && initialDockVerticalFraction <= 1,
       );

  static const dockHitTargetKey = Key('ai-pos-plugin-floating-dock-hit-target');
  static const scrimKey = Key('ai-pos-plugin-floating-scrim');

  static Key cardKey(String pluginId) =>
      ValueKey<String>('ai-pos-plugin-floating-card-$pluginId');

  static Key cardCloseKey(String pluginId) =>
      ValueKey<String>('ai-pos-plugin-floating-card-close-$pluginId');

  static Key cardCloseSurfaceKey(String pluginId) =>
      ValueKey<String>('ai-pos-plugin-floating-card-close-surface-$pluginId');

  static Key cardOpacityKey(String pluginId) =>
      ValueKey<String>('ai-pos-plugin-floating-card-opacity-$pluginId');

  static Key cardTransformKey(String pluginId) =>
      ValueKey<String>('ai-pos-plugin-floating-card-transform-$pluginId');

  final List<AiPosPluginFloatingCard> cards;
  final double revealExtent;
  final double initialDockVerticalFraction;
  final ValueChanged<double>? onDockVerticalFractionChanged;
  final String dockSemanticLabel;
  final String cardOpenSemanticLabel;
  final String cardCloseSemanticLabel;
  final AiPosPluginFloatingOverlayController? controller;
  final bool handleSystemBack;
  final AiPosPluginMotionPolicy motionPolicy;

  @override
  State<AiPosPluginFloatingOverlay> createState() =>
      _AiPosPluginFloatingOverlayState();
}

final class _AiPosPluginFloatingOverlayState
    extends State<AiPosPluginFloatingOverlay>
    with SingleTickerProviderStateMixin
    implements _AiPosPluginFloatingOverlayDelegate {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: 1,
  );
  late final ValueNotifier<bool> _dragging = ValueNotifier<bool>(false);
  bool _applicationActive = true;
  double _dragOriginX = 0;
  double _dragOriginProgress = 0;
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
  void didUpdateWidget(covariant AiPosPluginFloatingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (widget.cards.isEmpty) {
      _reveal.value = 0;
    }
  }

  void _notifyRevealProgress() {
    widget.controller?._update(_reveal.value);
  }

  @override
  double get revealProgress => _reveal.value;

  @override
  Future<void> collapse() => _settle(0, velocityX: 0);

  @override
  void setApplicationActive(bool active) {
    if (_applicationActive == active) {
      return;
    }
    _applicationActive = active;
    if (active) {
      return;
    }
    final target = _reveal.value < 0.5 ? 0.0 : 1.0;
    _reveal.stop(canceled: true);
    _reveal.value = target;
    _dragging.value = false;
  }

  void _toggle() {
    if (!_applicationActive) {
      return;
    }
    unawaited(_settle(_reveal.value < 0.5 ? 1 : 0, velocityX: 0));
  }

  void _onDragStart(DragStartDetails details) {
    if (!_applicationActive) {
      return;
    }
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
    if (!_applicationActive) {
      return;
    }
    _dragging.value = false;
    unawaited(_settle(0, velocityX: 0));
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
              builder: (context, constraints) {
                return Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    ..._buildCards(constraints),
                    _buildDock(constraints),
                  ],
                );
              },
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
          key: AiPosPluginFloatingOverlay.scrimKey,
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
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final cardWidth = math.min(240.0, width * 0.46);
    final cardHeight = math.min(height * 0.48, cardWidth * 1.55);
    final top = (height - cardHeight) / 2;
    final horizontalRange = math.max(0.0, width - cardWidth - 32);
    final dockCenterY = (_resolvedDockVerticalFraction * height).clamp(
      48.0,
      height - 48.0,
    );
    final dockRect = Rect.fromLTWH(width - 12, dockCenterY - 44, 56, 88);
    // Paint left cards last so every top-right close button stays visible when
    // the cards overlap like a deck.
    for (var index = count - 1; index >= 0; index -= 1) {
      final card = widget.cards[index];
      final finalLeft = count == 1
          ? (width - cardWidth) / 2
          : 16 + horizontalRange * index / (count - 1);
      final finalRect = Rect.fromLTWH(finalLeft, top, cardWidth, cardHeight);
      yield Positioned.fromRect(
        rect: finalRect,
        child: _FloatingCardProjection(
          card: card,
          reveal: _reveal,
          dragging: _dragging,
          dockRect: dockRect,
          expandedRect: finalRect,
          isLatest: index == count - 1,
          openSemanticLabel: widget.cardOpenSemanticLabel,
          closeSemanticLabel: widget.cardCloseSemanticLabel,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: _onDragCancel,
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
              key: AiPosPluginFloatingOverlay.dockHitTargetKey,
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
    super.dispose();
  }
}

final class _FloatingCardProjection extends StatelessWidget {
  const _FloatingCardProjection({
    required this.card,
    required this.reveal,
    required this.dragging,
    required this.dockRect,
    required this.expandedRect,
    required this.isLatest,
    required this.openSemanticLabel,
    required this.closeSemanticLabel,
    required this.onHorizontalDragStart,
    required this.onHorizontalDragUpdate,
    required this.onHorizontalDragEnd,
    required this.onHorizontalDragCancel,
  });

  final AiPosPluginFloatingCard card;
  final Animation<double> reveal;
  final ValueNotifier<bool> dragging;
  final Rect dockRect;
  final Rect expandedRect;
  final bool isLatest;
  final String openSemanticLabel;
  final String closeSemanticLabel;
  final GestureDragStartCallback onHorizontalDragStart;
  final GestureDragUpdateCallback onHorizontalDragUpdate;
  final GestureDragEndCallback onHorizontalDragEnd;
  final GestureDragCancelCallback onHorizontalDragCancel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([reveal, dragging]),
      child: RepaintBoundary(
        key: ValueKey<String>(
          'ai-pos-plugin-floating-card-repaint-${card.pluginId}',
        ),
        child: _FloatingCardSurface(
          card: card,
          openSemanticLabel: openSemanticLabel,
          closeSemanticLabel: closeSemanticLabel,
        ),
      ),
      builder: (context, child) {
        final progress = reveal.value;
        final cardProgress = isLatest
            ? _normalizedUnit(progress / 0.55)
            : _normalizedUnit((progress - 0.55) / 0.45);
        final currentRect = Rect.lerp(dockRect, expandedRect, cardProgress)!;
        final transform = Matrix4.identity()
          ..setEntry(0, 0, currentRect.width / expandedRect.width)
          ..setEntry(1, 1, currentRect.height / expandedRect.height)
          ..setEntry(0, 3, currentRect.left - expandedRect.left)
          ..setEntry(1, 3, currentRect.top - expandedRect.top);
        return Transform(
          alignment: Alignment.topLeft,
          transform: transform,
          child: GestureDetector(
            key: AiPosPluginFloatingOverlay.cardTransformKey(card.pluginId),
            behavior: HitTestBehavior.translucent,
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: onHorizontalDragStart,
            onHorizontalDragUpdate: onHorizontalDragUpdate,
            onHorizontalDragEnd: onHorizontalDragEnd,
            onHorizontalDragCancel: onHorizontalDragCancel,
            child: Opacity(
              key: AiPosPluginFloatingOverlay.cardOpacityKey(card.pluginId),
              opacity: cardProgress,
              child: IgnorePointer(
                ignoring: cardProgress < 1 || dragging.value,
                child: child,
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

  final AiPosPluginFloatingCard card;
  final String openSemanticLabel;
  final String closeSemanticLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: AiPosPluginFloatingOverlay.cardKey(card.pluginId),
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        label: '${openSemanticLabel.trim()} ${card.pluginName}',
        button: true,
        container: true,
        explicitChildNodes: true,
        child: InkWell(
          onTap: () {
            final box = context.findRenderObject();
            if (box is! RenderBox || !box.hasSize) {
              return;
            }
            card.onRestore(box.localToGlobal(Offset.zero) & box.size);
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
                          card.pluginName,
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
                  label: '${closeSemanticLabel.trim()} ${card.pluginName}',
                  button: true,
                  child: SizedBox(
                    key: AiPosPluginFloatingOverlay.cardCloseKey(card.pluginId),
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Material(
                        key: AiPosPluginFloatingOverlay.cardCloseSurfaceKey(
                          card.pluginId,
                        ),
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
