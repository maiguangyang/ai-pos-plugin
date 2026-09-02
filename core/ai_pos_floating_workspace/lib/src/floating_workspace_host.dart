import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'floating_dock.dart';
import 'floating_domain_controller.dart';
import 'floating_session.dart';
import 'floating_snapshot.dart';

typedef FloatingSnapshotCapture =
    Future<FloatingSnapshot> Function(
      RenderRepaintBoundary boundary,
      double pixelRatio,
    );

final class FloatingWorkspaceHost extends StatefulWidget {
  const FloatingWorkspaceHost({
    super.key,
    required this.domains,
    required this.child,
    this.snapshotPhysicalWidth = 480,
    this.snapshotCapture = _captureSnapshot,
    this.snapshotCaptureTimeout = const Duration(seconds: 3),
    this.onSnapshotCaptureFailed,
    this.backButtonDispatcher,
    this.dockSemanticLabel = 'Open floating windows',
    this.cardOpenSemanticLabel = 'Open',
    this.cardCloseSemanticLabel = 'Close',
  }) : assert(snapshotPhysicalWidth > 0),
       assert(snapshotCaptureTimeout > Duration.zero);

  static const dockKey = Key('ai-pos-floating-workspace-dock');
  static const floatProjectionKey = Key(
    'ai-pos-floating-workspace-float-projection',
  );
  static const restoreProjectionKey = Key(
    'ai-pos-floating-workspace-restore-projection',
  );
  static const openProjectionKey = Key(
    'ai-pos-floating-workspace-open-projection',
  );
  static const closeProjectionKey = Key(
    'ai-pos-floating-workspace-close-projection',
  );

  static Key foregroundSessionKey(FloatingSessionKey key) =>
      ValueKey<String>('ai-pos-floating-foreground-$key');

  final List<FloatingDomainController> domains;
  final Widget child;
  final int snapshotPhysicalWidth;
  final FloatingSnapshotCapture snapshotCapture;
  final Duration snapshotCaptureTimeout;
  final ValueChanged<FloatingSessionKey>? onSnapshotCaptureFailed;
  final BackButtonDispatcher? backButtonDispatcher;
  final String dockSemanticLabel;
  final String cardOpenSemanticLabel;
  final String cardCloseSemanticLabel;

  static Future<FloatingSnapshot> _captureSnapshot(
    RenderRepaintBoundary boundary,
    double pixelRatio,
  ) async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    return FloatingSnapshot.image(image);
  }

  @override
  State<FloatingWorkspaceHost> createState() => _FloatingWorkspaceHostState();
}

final class _FloatingWorkspaceHostState extends State<FloatingWorkspaceHost>
    with WidgetsBindingObserver, TickerProviderStateMixin
    implements FloatingDomainHostDelegate {
  final LinkedHashMap<FloatingSessionKey, _SessionEntry> _sessions =
      LinkedHashMap<FloatingSessionKey, _SessionEntry>();
  final Map<String, List<FloatingSessionKey>> _floatingOrder = {};
  final List<FloatingSessionKey> _presentationOrder = [];
  final Map<String, Future<void>> _closeAllFutures = {};
  final Map<FloatingSessionKey, _PendingReopen> _pendingReopens = {};
  final Map<String, _PendingProjectionOpen> _pendingProjectionOpens = {};
  final FloatingDockController _dockController = FloatingDockController();
  late final AnimationController _projectionAnimation;
  late final AnimationController _closeAnimation;
  ChildBackButtonDispatcher? _childBackButtonDispatcher;
  late final ValueGetter<Future<bool>> _systemBackCallback;
  _SessionProjection? _sessionProjection;
  _CloseProjection? _closeProjection;
  Future<void>? _activeTransition;
  FloatingSessionKey? _foregroundKey;
  double _dockVerticalFraction = 0.5;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _validateDomains(widget.domains);
    _projectionAnimation = AnimationController(vsync: this);
    _closeAnimation = AnimationController(vsync: this);
    _systemBackCallback = _handleSystemBack;
    _attachBackButtonDispatcher(widget.backButtonDispatcher);
    WidgetsBinding.instance.addObserver(this);
    for (final domain in widget.domains) {
      domain.attachHost(this);
      _floatingOrder[domain.domainId] = <FloatingSessionKey>[];
    }
  }

  @override
  void didUpdateWidget(covariant FloatingWorkspaceHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.backButtonDispatcher,
      widget.backButtonDispatcher,
    )) {
      _attachBackButtonDispatcher(widget.backButtonDispatcher);
    }
    if (_sameDomains(oldWidget.domains, widget.domains)) {
      return;
    }
    _validateDomains(widget.domains);

    final oldById = {
      for (final domain in oldWidget.domains) domain.domainId: domain,
    };
    final newById = {
      for (final domain in widget.domains) domain.domainId: domain,
    };
    for (final entry in oldById.entries) {
      final replacement = newById[entry.key];
      if (identical(entry.value, replacement)) {
        continue;
      }
      if (_sessions.keys.any((key) => key.domainId == entry.key)) {
        throw StateError(
          'Domain ${entry.key} cannot change while its sessions are active.',
        );
      }
    }

    for (final entry in oldById.entries) {
      if (!identical(entry.value, newById[entry.key])) {
        entry.value.detachHost(this);
        _floatingOrder.remove(entry.key);
        _presentationOrder.removeWhere((key) => key.domainId == entry.key);
      }
    }
    for (final entry in newById.entries) {
      if (!identical(entry.value, oldById[entry.key])) {
        entry.value.attachHost(this);
        _floatingOrder[entry.key] = <FloatingSessionKey>[];
      }
    }
  }

  void _attachBackButtonDispatcher(BackButtonDispatcher? dispatcher) {
    _childBackButtonDispatcher?.removeCallback(_systemBackCallback);
    _childBackButtonDispatcher = null;
    if (dispatcher == null) return;
    final child = dispatcher.createChildBackButtonDispatcher()
      ..addCallback(_systemBackCallback);
    _childBackButtonDispatcher = child;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_childBackButtonDispatcher, child)) {
        child.takePriority();
      }
    });
  }

  bool _sameDomains(
    List<FloatingDomainController> left,
    List<FloatingDomainController> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!identical(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  void _validateDomains(List<FloatingDomainController> domains) {
    final ids = <String>{};
    for (final domain in domains) {
      if (!ids.add(domain.domainId)) {
        throw ArgumentError('Duplicate floating domain: ${domain.domainId}');
      }
    }
  }

  @override
  Future<Object?> open(
    FloatingDomainController controller,
    FloatingSessionRequest request,
  ) {
    _requireOwnedController(controller);
    if (_disposed || !mounted) {
      throw StateError('The floating workspace host is disposed.');
    }
    if (_closeAllFutures.containsKey(controller.domainId)) {
      throw StateError('The floating domain is closing all sessions.');
    }
    final existing = _sessions[request.key];
    if (existing != null) {
      if (existing.closeFuture != null ||
          existing.visibility == FloatingSessionVisibility.closing) {
        final pending = _PendingReopen(request);
        final previous = _pendingReopens[request.key];
        if (previous == null) {
          _pendingReopens[request.key] = pending;
          unawaited(_openAfterClose(controller, existing));
        } else {
          previous.completeSuperseded();
          _pendingReopens[request.key] = pending;
        }
        return pending.completion.future;
      }
      final foreground = _foregroundEntry;
      if (foreground != null &&
          !identical(foreground, existing) &&
          foreground.request.key.domainId != request.key.domainId) {
        throw FloatingWorkspaceBusyException(
          requested: request.key,
          foreground: foreground.request.key,
        );
      }
      unawaited(_restore(existing));
      return existing.completion.future;
    }
    final projection = _sessionProjection;
    if (projection != null) {
      if (projection.entry.request.key.domainId == request.key.domainId) {
        final pending = _PendingProjectionOpen(request);
        _pendingProjectionOpens.update(request.key.domainId, (previous) {
          previous.completeSuperseded();
          return pending;
        }, ifAbsent: () => pending);
        if (projection.kind == _SessionProjectionKind.opening) {
          _cancelInitialPresentation(projection.entry);
        }
        return pending.completion.future;
      }
      throw FloatingWorkspaceBusyException(
        requested: request.key,
        foreground: projection.entry.request.key,
      );
    }
    final foreground = _foregroundEntry;
    if (foreground != null) {
      if (foreground.request.key.domainId == request.key.domainId) {
        return _replaceForegroundAndOpen(controller, request, foreground);
      }
      throw FloatingWorkspaceBusyException(
        requested: request.key,
        foreground: foreground.request.key,
      );
    }
    final entry = _installNewEntry(request);
    return entry.completion.future;
  }

  _SessionEntry _installNewEntry(FloatingSessionRequest request) {
    final entry = _SessionEntry(request)
      ..initialPresentationPending = request.animateInitialPresentation;
    _sessions[request.key] = entry;
    _foregroundKey = request.key;
    setState(() {});
    if (entry.initialPresentationPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isCurrent(entry)) {
          unawaited(_startInitialPresentation(entry));
        }
      });
    } else {
      unawaited(_notifyVisibility(entry, FloatingSessionVisibility.foreground));
    }
    return entry;
  }

  Future<void> _startInitialPresentation(_SessionEntry entry) {
    final current = entry.initialPresentationFuture;
    if (current != null) return current;
    final operation = _enqueueTransition(
      () => _performInitialPresentation(entry),
    );
    entry.initialPresentationFuture = operation;
    unawaited(
      operation.then<void>(
        (_) => _clearInitialPresentationFuture(entry, operation),
        onError: (_, _) => _clearInitialPresentationFuture(entry, operation),
      ),
    );
    return operation;
  }

  void _clearInitialPresentationFuture(
    _SessionEntry entry,
    Future<void> operation,
  ) {
    if (identical(entry.initialPresentationFuture, operation)) {
      entry.initialPresentationFuture = null;
    }
  }

  Future<void> _performInitialPresentation(_SessionEntry entry) async {
    if (!_isCurrent(entry) || !entry.initialPresentationPending) return;
    final snapshot = await _captureInitialSnapshot(entry);
    if (!mounted || !_isCurrent(entry)) {
      snapshot?.dispose();
      return;
    }
    if (entry.initialPresentationCancelled) {
      snapshot?.dispose();
      await _openLatestProjectionRequest(entry.request.key.domainId);
      return;
    }
    if (snapshot == null) {
      await _completeInitialPresentation(entry);
      return;
    }
    final viewport = MediaQuery.sizeOf(context);
    final sourceRect = _validLaunchSourceRect(
      entry.request.launchOrigin,
      viewport,
    );
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    _sessionProjection = _SessionProjection(
      entry: entry,
      snapshot: snapshot,
      startRect: reducedMotion
          ? Offset.zero & viewport
          : sourceRect ?? _centeredFallbackRect(viewport),
      endRect: Offset.zero & viewport,
      kind: _SessionProjectionKind.opening,
      reducedMotion: reducedMotion,
    );
    setState(() {});
    await _runProjectionAnimation(_sessionProjection!);
    final initialPresentationCancelled = entry.initialPresentationCancelled;
    if (!mounted ||
        !_isCurrent(entry) ||
        initialPresentationCancelled ||
        !identical(_sessionProjection?.entry, entry)) {
      if (identical(_sessionProjection?.snapshot, snapshot)) {
        _sessionProjection = null;
      }
      snapshot.dispose();
      if (mounted && _isCurrent(entry) && initialPresentationCancelled) {
        await _openLatestProjectionRequest(entry.request.key.domainId);
      }
      return;
    }
    _sessionProjection = null;
    if (!reducedMotion && sourceRect != null) {
      entry.reverseLaunchOrigin = entry.request.launchOrigin;
    }
    await _completeInitialPresentation(entry);
    snapshot.dispose();
    await _openLatestProjectionRequest(entry.request.key.domainId);
  }

  Future<void> _completeInitialPresentation(_SessionEntry entry) async {
    if (!_isCurrent(entry)) return;
    await _notifyVisibility(entry, FloatingSessionVisibility.foreground);
    if (!_isCurrent(entry)) return;
    entry.initialPresentationPending = false;
    if (mounted) setState(() {});
  }

  Rect _centeredFallbackRect(Size viewport) {
    return Rect.fromCenter(
      center: Offset(viewport.width / 2, viewport.height / 2),
      width: viewport.width * 0.96,
      height: viewport.height * 0.96,
    );
  }

  Rect? _validLaunchSourceRect(
    FloatingSessionLaunchOrigin? origin,
    Size viewport,
  ) {
    if (origin == null ||
        (origin.viewportSize.width - viewport.width).abs() > 0.5 ||
        (origin.viewportSize.height - viewport.height).abs() > 0.5) {
      return null;
    }
    final rect = origin.sourceRect;
    if (!rect.left.isFinite ||
        !rect.top.isFinite ||
        !rect.right.isFinite ||
        !rect.bottom.isFinite ||
        rect.width <= 0 ||
        rect.height <= 0 ||
        !rect.overlaps(Offset.zero & viewport)) {
      return null;
    }
    return rect;
  }

  Future<void> _openAfterClose(
    FloatingDomainController controller,
    _SessionEntry closing,
  ) async {
    try {
      await closing.closeFuture;
    } catch (error, stackTrace) {
      _pendingReopens
          .remove(closing.request.key)
          ?.completeError(error, stackTrace);
      return;
    }
    final pending = _pendingReopens.remove(closing.request.key);
    if (pending == null) return;
    if (_closeAllFutures.containsKey(controller.domainId)) {
      pending.completeSuperseded();
      return;
    }
    try {
      pending.completeWith(open(controller, pending.request));
    } catch (error, stackTrace) {
      pending.completeError(error, stackTrace);
    }
  }

  Future<Object?> _replaceForegroundAndOpen(
    FloatingDomainController controller,
    FloatingSessionRequest request,
    _SessionEntry foreground,
  ) async {
    await _closeEntry(foreground, null);
    return await open(controller, request);
  }

  @override
  Future<void> close(FloatingDomainController controller, String sessionId) {
    _requireOwnedController(controller);
    final closeAll = _closeAllFutures[controller.domainId];
    if (closeAll != null) return closeAll;
    final key = FloatingSessionKey(
      domainId: controller.domainId,
      sessionId: sessionId,
    );
    final entry = _sessions[key];
    return entry == null ? Future<void>.value() : _closeEntry(entry, null);
  }

  @override
  Future<void> closeAll(FloatingDomainController controller) {
    _requireOwnedController(controller);
    final current = _closeAllFutures[controller.domainId];
    if (current != null) {
      return current;
    }
    final pendingReopenKeys = _pendingReopens.keys
        .where((key) => key.domainId == controller.domainId)
        .toList(growable: false);
    for (final key in pendingReopenKeys) {
      _pendingReopens.remove(key)?.completeSuperseded();
    }
    _pendingProjectionOpens.remove(controller.domainId)?.completeSuperseded();
    for (final entry in _sessions.values.where(
      (entry) => entry.request.key.domainId == controller.domainId,
    )) {
      _cancelInitialPresentation(entry);
    }
    late final Future<void> operation;
    operation = _enqueueTransition(() => _performCloseAll(controller.domainId))
        .whenComplete(() {
          if (identical(_closeAllFutures[controller.domainId], operation)) {
            _closeAllFutures.remove(controller.domainId);
          }
        });
    _closeAllFutures[controller.domainId] = operation;
    return operation;
  }

  @override
  int sessionCount(FloatingDomainController controller) {
    _requireOwnedController(controller);
    return _sessions.keys
        .where((key) => key.domainId == controller.domainId)
        .length;
  }

  void _requireOwnedController(FloatingDomainController controller) {
    if (!widget.domains.any((domain) => identical(domain, controller))) {
      throw ArgumentError('Controller is not owned by this workspace.');
    }
  }

  _SessionEntry? get _foregroundEntry {
    final key = _foregroundKey;
    return key == null ? null : _sessions[key];
  }

  Future<FloatingSnapshot?> _captureInitialSnapshot(_SessionEntry entry) async {
    final boundary = entry.repaintBoundaryKey.currentContext
        ?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
      widget.onSnapshotCaptureFailed?.call(entry.request.key);
      return null;
    }
    var timedOut = false;
    final capture = Future<FloatingSnapshot>.sync(
      () => widget.snapshotCapture(
        boundary,
        _capturePixelRatio(entry, boundary.size),
      ),
    );
    try {
      final snapshot = await Future.any<FloatingSnapshot?>([
        capture.timeout(
          widget.snapshotCaptureTimeout,
          onTimeout: () {
            timedOut = true;
            throw TimeoutException(
              'Floating initial snapshot capture timed out.',
            );
          },
        ),
        entry.initialPresentationCancellation.future.then((_) => null),
      ]);
      if (snapshot == null || entry.initialPresentationCancelled) {
        unawaited(
          capture.then<void>(
            (lateSnapshot) => lateSnapshot.dispose(),
            onError: (_, _) {},
          ),
        );
        return null;
      }
      final policy = _policyFor(entry.request.key.domainId);
      if (snapshot.width > widget.snapshotPhysicalWidth ||
          snapshot.estimatedBytes > policy.maxSnapshotBytes) {
        snapshot.dispose();
        widget.onSnapshotCaptureFailed?.call(entry.request.key);
        return null;
      }
      return snapshot;
    } catch (_) {
      if (timedOut) {
        unawaited(
          capture.then<void>(
            (lateSnapshot) => lateSnapshot.dispose(),
            onError: (_, _) {},
          ),
        );
      }
      if (!entry.initialPresentationCancelled) {
        widget.onSnapshotCaptureFailed?.call(entry.request.key);
      }
      return null;
    }
  }

  void _cancelInitialPresentation(_SessionEntry entry) {
    if (!entry.initialPresentationPending ||
        entry.initialPresentationCancelled) {
      return;
    }
    entry.initialPresentationCancelled = true;
    entry.initialPresentationCancellation.complete();
    final projection = _sessionProjection;
    if (projection?.kind == _SessionProjectionKind.opening &&
        identical(projection?.entry, entry)) {
      _projectionAnimation.stop(canceled: true);
    }
  }

  Future<void> _float(_SessionEntry entry) {
    final current = entry.floatFuture;
    if (current != null) {
      return current;
    }
    if (!mounted ||
        !_isCurrent(entry) ||
        entry.visibility != FloatingSessionVisibility.foreground) {
      return Future<void>.value();
    }
    final operation = _enqueueTransition(() => _performFloat(entry));
    entry.floatFuture = operation;
    unawaited(
      operation.then<void>(
        (_) {
          if (identical(entry.floatFuture, operation)) {
            entry.floatFuture = null;
          }
        },
        onError: (_, _) {
          if (identical(entry.floatFuture, operation)) {
            entry.floatFuture = null;
          }
        },
      ),
    );
    return operation;
  }

  Future<void> _performFloat(_SessionEntry entry) async {
    entry.reverseLaunchOrigin = null;
    await WidgetsBinding.instance.endOfFrame;
    if (!_isCurrent(entry) ||
        entry.visibility != FloatingSessionVisibility.foreground) {
      return;
    }
    final boundary = entry.repaintBoundaryKey.currentContext
        ?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
      widget.onSnapshotCaptureFailed?.call(entry.request.key);
      return;
    }
    FloatingSnapshot snapshot;
    var timedOut = false;
    final capture = Future<FloatingSnapshot>.sync(
      () => widget.snapshotCapture(
        boundary,
        _capturePixelRatio(entry, boundary.size),
      ),
    );
    try {
      snapshot = await capture.timeout(
        widget.snapshotCaptureTimeout,
        onTimeout: () {
          timedOut = true;
          throw TimeoutException('Floating snapshot capture timed out.');
        },
      );
    } catch (_) {
      if (timedOut) {
        unawaited(
          capture.then<void>(
            (lateSnapshot) => lateSnapshot.dispose(),
            onError: (_, _) {},
          ),
        );
      }
      widget.onSnapshotCaptureFailed?.call(entry.request.key);
      return;
    }
    if (!_isCurrent(entry) ||
        entry.visibility != FloatingSessionVisibility.foreground) {
      snapshot.dispose();
      return;
    }
    final policy = _policyFor(entry.request.key.domainId);
    if (snapshot.width > widget.snapshotPhysicalWidth ||
        snapshot.estimatedBytes > policy.maxSnapshotBytes) {
      snapshot.dispose();
      widget.onSnapshotCaptureFailed?.call(entry.request.key);
      return;
    }
    entry.snapshot = snapshot;
    _foregroundKey = null;
    await _notifyVisibility(entry, FloatingSessionVisibility.floating);
    if (!mounted || !_isCurrent(entry)) {
      snapshot.dispose();
      return;
    }
    final order = _floatingOrder[entry.request.key.domainId]!;
    if (!order.contains(entry.request.key)) {
      order.add(entry.request.key);
    }
    _presentationOrder.remove(entry.request.key);
    _presentationOrder.add(entry.request.key);
    _sessionProjection = _SessionProjection(
      entry: entry,
      snapshot: snapshot,
      startRect: Offset.zero & MediaQuery.sizeOf(context),
      endRect: _dockProjectionRect(MediaQuery.sizeOf(context)),
      kind: _SessionProjectionKind.floating,
      reducedMotion: MediaQuery.disableAnimationsOf(context),
    );
    if (mounted) setState(() {});
    await _runProjectionAnimation(_sessionProjection!);
    if (!_isCurrent(entry) || !identical(_sessionProjection?.entry, entry)) {
      return;
    }
    _sessionProjection = null;
    if (mounted) {
      setState(() {});
    }
    await _evictOverflow(entry.request.key.domainId);
    await _openLatestProjectionRequest(entry.request.key.domainId);
  }

  Future<void> _openLatestProjectionRequest(String domainId) async {
    final pending = _pendingProjectionOpens.remove(domainId);
    if (pending == null) return;
    if (_disposed || !mounted || _closeAllFutures.containsKey(domainId)) {
      pending.completeSuperseded();
      return;
    }
    final foreground = _foregroundEntry;
    if (foreground != null) {
      if (foreground.request.key.domainId != domainId) {
        pending.completeError(
          FloatingWorkspaceBusyException(
            requested: pending.request.key,
            foreground: foreground.request.key,
          ),
        );
        return;
      }
      await _closeEntryWithinTransition(foreground, null);
      if (_disposed || !mounted) {
        pending.completeSuperseded();
        return;
      }
    }
    final entry = _installNewEntry(pending.request);
    pending.completeWith(entry.completion.future);
  }

  Rect _dockProjectionRect(Size logicalSize) {
    final safePadding = MediaQuery.paddingOf(context);
    final safeHeight = math.max(0.0, logicalSize.height - safePadding.vertical);
    final halfDockHitTargetHeight = math.min(48.0, safeHeight / 2);
    final safeCenterY = (_dockVerticalFraction * safeHeight).clamp(
      halfDockHitTargetHeight,
      safeHeight - halfDockHitTargetHeight,
    );
    return Rect.fromLTWH(
      logicalSize.width - 22,
      safePadding.top + safeCenterY - 44,
      22,
      88,
    );
  }

  Future<void> _runProjectionAnimation(_SessionProjection projection) async {
    _projectionAnimation
      ..duration = projection.reducedMotion
          ? projection.kind == _SessionProjectionKind.opening
                ? const Duration(milliseconds: 100)
                : const Duration(milliseconds: 120)
          : switch (projection.kind) {
              _SessionProjectionKind.opening => const Duration(
                milliseconds: 300,
              ),
              _SessionProjectionKind.floating => const Duration(
                milliseconds: 340,
              ),
              _SessionProjectionKind.restoring => const Duration(
                milliseconds: 360,
              ),
            }
      ..value = 0;
    try {
      await _projectionAnimation.forward().orCancel;
    } on TickerCanceled {
      // Disposal or a newer transition owns the final state.
    }
  }

  double _capturePixelRatio(_SessionEntry entry, Size logicalSize) {
    final policy = _policyFor(entry.request.key.domainId);
    final deviceRatio = MediaQuery.devicePixelRatioOf(context);
    final widthRatio = widget.snapshotPhysicalWidth / logicalSize.width;
    final retainedBytes = _retainedSnapshotBytes(entry.request.key.domainId);
    final availableBytes = math.max(4, policy.maxSnapshotBytes - retainedBytes);
    final logicalByteArea = logicalSize.width * logicalSize.height * 4;
    final budgetRatio = math.sqrt(availableBytes / logicalByteArea);
    return math.max(
      0.001,
      math.min(deviceRatio, math.min(widthRatio, budgetRatio)),
    );
  }

  Future<void> _evictOverflow(String domainId) async {
    final policy = _policyFor(domainId);
    final order = _floatingOrder[domainId]!;
    while (order.length > policy.maxFloatingSessions ||
        _retainedSnapshotBytes(domainId) > policy.maxSnapshotBytes) {
      final oldestKey = order.first;
      final oldest = _sessions[oldestKey];
      if (oldest == null) {
        order.removeAt(0);
      } else {
        await _closeEntryWithinTransition(oldest, null);
      }
    }
  }

  int _retainedSnapshotBytes(String domainId) {
    return _floatingOrder[domainId]!.fold<int>(0, (sum, key) {
      return sum + (_sessions[key]?.snapshot?.estimatedBytes ?? 0);
    });
  }

  FloatingDomainPolicy _policyFor(String domainId) {
    return widget.domains
        .firstWhere((domain) => domain.domainId == domainId)
        .policy;
  }

  Future<void> _restore(_SessionEntry entry, {Rect? sourceRect}) {
    final current = entry.restoreFuture;
    if (current != null) return current;
    final operation = _enqueueTransition(
      () => _performRestore(entry, sourceRect: sourceRect),
    );
    entry.restoreFuture = operation;
    unawaited(
      operation.then<void>(
        (_) {
          if (identical(entry.restoreFuture, operation)) {
            entry.restoreFuture = null;
          }
        },
        onError: (_, _) {
          if (identical(entry.restoreFuture, operation)) {
            entry.restoreFuture = null;
          }
        },
      ),
    );
    return operation;
  }

  Future<void> _performRestore(_SessionEntry entry, {Rect? sourceRect}) async {
    if (!_isCurrent(entry)) {
      return;
    }
    if (entry.visibility == FloatingSessionVisibility.foreground) {
      return;
    }
    entry.reverseLaunchOrigin = null;
    final foreground = _foregroundEntry;
    if (foreground != null && !identical(foreground, entry)) {
      if (foreground.request.key.domainId != entry.request.key.domainId) {
        return;
      }
      await _closeEntryWithinTransition(foreground, null);
      if (!mounted || !_isCurrent(entry)) return;
    }
    _floatingOrder[entry.request.key.domainId]!.remove(entry.request.key);
    _presentationOrder.remove(entry.request.key);
    final snapshot = entry.snapshot;
    if (snapshot == null) return;
    unawaited(_dockController.collapse());
    _sessionProjection = _SessionProjection(
      entry: entry,
      snapshot: snapshot,
      startRect: sourceRect ?? _dockProjectionRect(MediaQuery.sizeOf(context)),
      endRect: Offset.zero & MediaQuery.sizeOf(context),
      kind: _SessionProjectionKind.restoring,
      reducedMotion: MediaQuery.disableAnimationsOf(context),
    );
    if (mounted) setState(() {});
    await _runProjectionAnimation(_sessionProjection!);
    if (!_isCurrent(entry) || !identical(_sessionProjection?.entry, entry)) {
      return;
    }
    _sessionProjection = null;
    _foregroundKey = entry.request.key;
    entry.snapshot = null;
    await _notifyVisibility(entry, FloatingSessionVisibility.foreground);
    if (mounted) setState(() {});
    snapshot.dispose();
    await _openLatestProjectionRequest(entry.request.key.domainId);
  }

  Future<void> _restart(_SessionEntry entry) async {
    if (!_isCurrent(entry)) {
      return;
    }
    final request = entry.request;
    await _closeEntry(entry, null);
    await WidgetsBinding.instance.endOfFrame;
    if (!_disposed &&
        mounted &&
        _foregroundEntry == null &&
        !_closeAllFutures.containsKey(request.key.domainId)) {
      unawaited(open(_controllerFor(request.key.domainId), request));
    }
  }

  FloatingDomainController _controllerFor(String domainId) {
    return widget.domains.firstWhere((domain) => domain.domainId == domainId);
  }

  Future<void> _closeEntry(_SessionEntry entry, Object? result) {
    _cancelInitialPresentation(entry);
    final closeAll = _closeAllFutures[entry.request.key.domainId];
    if (closeAll != null) return closeAll;
    final current = entry.closeFuture;
    if (current != null) {
      return current;
    }
    final operation = _enqueueTransition(
      () => _performCloseEntry(entry, result),
    );
    entry.closeFuture = operation;
    return operation;
  }

  Future<void> _closeEntryWithinTransition(
    _SessionEntry entry,
    Object? result,
  ) {
    if (!_isCurrent(entry)) return Future<void>.value();
    if (entry.visibility == FloatingSessionVisibility.closing) {
      return entry.closeFuture ?? Future<void>.value();
    }
    final operation = _performCloseEntry(entry, result);
    entry.closeFuture ??= operation;
    return operation;
  }

  Future<void> _performCloseEntry(_SessionEntry entry, Object? result) async {
    if (!_isCurrent(entry)) {
      return;
    }
    final wasPendingInitialPresentation = entry.initialPresentationPending;
    final wasForeground = _foregroundKey == entry.request.key;
    final closeSnapshot = wasForeground && !wasPendingInitialPresentation
        ? await _captureCloseSnapshot(entry)
        : null;
    if (!mounted || !_isCurrent(entry)) {
      closeSnapshot?.dispose();
      return;
    }
    await _notifyVisibility(entry, FloatingSessionVisibility.closing);
    if (!mounted || !_isCurrent(entry)) {
      closeSnapshot?.dispose();
      return;
    }
    _floatingOrder[entry.request.key.domainId]!.remove(entry.request.key);
    _presentationOrder.remove(entry.request.key);
    final snapshot = entry.snapshot;
    entry.snapshot = null;
    if (closeSnapshot != null) {
      final viewport = MediaQuery.sizeOf(context);
      final targetRect = MediaQuery.disableAnimationsOf(context)
          ? null
          : _validLaunchSourceRect(entry.reverseLaunchOrigin, viewport);
      _closeProjection = _CloseProjection(
        snapshot: closeSnapshot,
        logicalSize: viewport,
        reducedMotion: MediaQuery.disableAnimationsOf(context),
        targetRect: targetRect,
      );
    }
    if (mounted) {
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
    }
    snapshot?.dispose();
    if (!mounted || !_isCurrent(entry)) {
      closeSnapshot?.dispose();
      return;
    }
    if (closeSnapshot != null) {
      _closeAnimation
        ..duration = _closeProjection!.reducedMotion
            ? const Duration(milliseconds: 120)
            : const Duration(milliseconds: 300)
        ..value = 0;
      try {
        await _closeAnimation.forward().orCancel;
      } on TickerCanceled {
        // Disposal owns the remaining snapshot cleanup.
      }
      if (identical(_closeProjection?.snapshot, closeSnapshot)) {
        _closeProjection = null;
        closeSnapshot.dispose();
        if (mounted) setState(() {});
      }
    }
    _sessions.remove(entry.request.key);
    if (_foregroundKey == entry.request.key) {
      _foregroundKey = null;
    }
    if (mounted) setState(() {});
    try {
      await entry.request.onClosed(result);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'while closing a floating session');
    }
    if (!entry.completion.isCompleted) {
      entry.completion.complete(result);
    }
  }

  Future<FloatingSnapshot?> _captureCloseSnapshot(_SessionEntry entry) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!_isCurrent(entry) || _foregroundKey != entry.request.key) return null;
    final boundary = entry.repaintBoundaryKey.currentContext
        ?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return null;
    var timedOut = false;
    final capture = Future<FloatingSnapshot>.sync(
      () => widget.snapshotCapture(
        boundary,
        _capturePixelRatio(entry, boundary.size),
      ),
    );
    try {
      final snapshot = await capture.timeout(
        widget.snapshotCaptureTimeout,
        onTimeout: () {
          timedOut = true;
          throw TimeoutException('Floating close snapshot capture timed out.');
        },
      );
      final policy = _policyFor(entry.request.key.domainId);
      if (snapshot.width > widget.snapshotPhysicalWidth ||
          snapshot.estimatedBytes > policy.maxSnapshotBytes) {
        snapshot.dispose();
        return null;
      }
      return snapshot;
    } catch (_) {
      if (timedOut) {
        unawaited(
          capture.then<void>(
            (lateSnapshot) => lateSnapshot.dispose(),
            onError: (_, _) {},
          ),
        );
      }
      return null;
    }
  }

  Future<void> _performCloseAll(String domainId) async {
    final entries = _sessions.values
        .where((entry) => entry.request.key.domainId == domainId)
        .toList(growable: false);
    await Future.wait(
      entries.map((entry) => _closeEntryWithinTransition(entry, null)),
    );
  }

  Future<void> _enqueueTransition(Future<void> Function() operation) {
    final active = _activeTransition;
    final queued = active == null
        ? Future<void>.sync(operation)
        : active.then((_) => operation(), onError: (_, _) => operation());
    _activeTransition = queued;
    unawaited(
      queued.then<void>(
        (_) => _clearActiveTransition(queued),
        onError: (_, _) => _clearActiveTransition(queued),
      ),
    );
    return queued;
  }

  void _clearActiveTransition(Future<void> operation) {
    if (identical(_activeTransition, operation)) {
      _activeTransition = null;
    }
  }

  bool _isCurrent(_SessionEntry entry) {
    return !_disposed && identical(_sessions[entry.request.key], entry);
  }

  Future<void> _notifyVisibility(
    _SessionEntry entry,
    FloatingSessionVisibility visibility,
  ) async {
    entry.visibility = visibility;
    try {
      await entry.request.onVisibilityChanged(visibility);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'while changing floating session visibility');
    }
  }

  void _report(Object error, StackTrace stackTrace, String description) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'ai_pos_floating_workspace',
        context: ErrorDescription(description),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _dockController.setApplicationActive(state == AppLifecycleState.resumed);
  }

  Future<bool> _handleSystemBack() async {
    if (_sessionProjection != null || _closeProjection != null) {
      return true;
    }
    if (_dockController.isExpanded) {
      await _dockController.collapse();
      return true;
    }
    final foreground = _foregroundEntry;
    if (foreground == null) {
      return false;
    }
    if (await foreground.request.maybePopNested()) {
      return true;
    }
    await _closeEntry(foreground, null);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final blocksChild =
        _foregroundEntry != null ||
        _sessionProjection != null ||
        _closeProjection != null;
    final content = Stack(
      fit: StackFit.expand,
      children: [
        for (final entry in _sessions.values)
          if (entry.initialPresentationPending) _buildSession(entry),
        ExcludeSemantics(
          excluding: blocksChild,
          child: IgnorePointer(ignoring: blocksChild, child: widget.child),
        ),
        for (final entry in _sessions.values)
          if (!entry.initialPresentationPending) _buildSession(entry),
        if (_presentationOrder.isNotEmpty)
          KeyedSubtree(
            key: FloatingWorkspaceHost.dockKey,
            child: FloatingDock(
              controller: _dockController,
              handleSystemBack: false,
              initialDockVerticalFraction: _dockVerticalFraction,
              onDockVerticalFractionChanged: (value) {
                _dockVerticalFraction = value;
              },
              dockSemanticLabel: widget.dockSemanticLabel,
              cardOpenSemanticLabel: widget.cardOpenSemanticLabel,
              cardCloseSemanticLabel: widget.cardCloseSemanticLabel,
              cards: [
                for (final key in _presentationOrder)
                  if (_sessions[key] case final entry?) _buildCard(entry),
              ],
            ),
          ),
        if (_sessionProjection case final projection?)
          _buildSessionProjection(projection),
        if (_closeProjection case final projection?)
          _buildCloseProjection(projection),
      ],
    );
    return PopScope<void>(
      canPop: !blocksChild && !_dockController.isExpanded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_handleSystemBack());
        }
      },
      child: Overlay.maybeOf(context) == null
          ? Overlay.wrap(child: content)
          : content,
    );
  }

  Widget _buildSessionProjection(_SessionProjection projection) {
    final isFloating = projection.kind == _SessionProjectionKind.floating;
    final isOpening = projection.kind == _SessionProjectionKind.opening;
    return Positioned.fill(
      key: isOpening
          ? FloatingWorkspaceHost.openProjectionKey
          : isFloating
          ? FloatingWorkspaceHost.floatProjectionKey
          : FloatingWorkspaceHost.restoreProjectionKey,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _projectionAnimation,
          builder: (context, _) {
            final rawProgress = _projectionAnimation.value;
            final progress = projection.reducedMotion
                ? rawProgress
                : (isFloating ? Curves.easeInOutCubic : Curves.easeOutCubic)
                      .transform(rawProgress);
            final rect = projection.reducedMotion
                ? projection.endRect
                : Rect.lerp(
                    projection.startRect,
                    projection.endRect,
                    progress,
                  )!;
            final opacity = projection.reducedMotion
                ? (isFloating ? 1 - rawProgress : rawProgress)
                : isOpening && projection.startRect != projection.endRect
                ? rawProgress
                : 1.0;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: Opacity(
                    opacity: opacity,
                    child: PhysicalModel(
                      color: Theme.of(context).colorScheme.surface,
                      elevation: projection.reducedMotion ? 0 : 12,
                      borderRadius: BorderRadius.circular(
                        projection.reducedMotion
                            ? 0
                            : 18 * (isFloating ? progress : 1 - progress),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: projection.snapshot.build(fit: BoxFit.fill),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCloseProjection(_CloseProjection projection) {
    return Positioned.fill(
      key: FloatingWorkspaceHost.closeProjectionKey,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _closeAnimation,
          child: projection.snapshot.build(fit: BoxFit.fill),
          builder: (context, child) {
            final progress = _closeAnimation.value;
            final targetRect = projection.targetRect;
            if (targetRect != null) {
              final transformedProgress = Curves.easeOutCubic.transform(
                progress,
              );
              final rect = Rect.lerp(
                Offset.zero & projection.logicalSize,
                targetRect,
                transformedProgress,
              )!;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fromRect(
                    rect: rect,
                    child: PhysicalModel(
                      color: Theme.of(context).colorScheme.surface,
                      elevation: 12 * (1 - transformedProgress),
                      borderRadius: BorderRadius.circular(
                        18 * transformedProgress,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: child,
                    ),
                  ),
                ],
              );
            }
            final offset = projection.reducedMotion
                ? Offset.zero
                : Offset(
                    -0.28 * projection.logicalSize.width * progress,
                    0.16 * projection.logicalSize.height * progress,
                  );
            final scale = projection.reducedMotion ? 1.0 : 1 - 0.18 * progress;
            return Opacity(
              opacity: 1 - progress,
              child: Transform.translate(
                offset: offset,
                child: Transform.scale(
                  alignment: Alignment.center,
                  scale: scale,
                  child: child,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSession(_SessionEntry entry) {
    final foreground = entry.visibility == FloatingSessionVisibility.foreground;
    return Offstage(
      offstage: !foreground,
      child: TickerMode(
        enabled: foreground && !entry.initialPresentationPending,
        child: ExcludeSemantics(
          excluding: entry.initialPresentationPending,
          child: IgnorePointer(
            ignoring: !foreground || entry.initialPresentationPending,
            child: RepaintBoundary(
              key: entry.repaintBoundaryKey,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Builder(
                    builder: (context) => entry.request.pageBuilder(
                      context,
                      _EntryActions(this, entry),
                    ),
                  ),
                  if (foreground && !entry.initialPresentationPending)
                    IgnorePointer(
                      child: SizedBox.expand(
                        key: FloatingWorkspaceHost.foregroundSessionKey(
                          entry.request.key,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  FloatingDockCard _buildCard(_SessionEntry entry) {
    return FloatingDockCard(
      id: entry.request.key,
      title: entry.request.title,
      snapshot: entry.snapshot!,
      onRestore: (rect) => unawaited(_restore(entry, sourceRect: rect)),
      onClose: () => unawaited(_closeEntry(entry, null)),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _childBackButtonDispatcher?.removeCallback(_systemBackCallback);
    _childBackButtonDispatcher = null;
    for (final entry in _sessions.values) {
      _cancelInitialPresentation(entry);
    }
    _projectionAnimation.dispose();
    _closeAnimation.dispose();
    _closeProjection?.snapshot.dispose();
    _closeProjection = null;
    for (final domain in widget.domains) {
      domain.detachHost(this);
    }
    for (final entry in _sessions.values) {
      entry.snapshot?.dispose();
      unawaited(
        Future<void>.sync(
          () => entry.request.onVisibilityChanged(
            FloatingSessionVisibility.closing,
          ),
        ).then((_) => entry.request.onClosed(null)).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          _report(error, stackTrace, 'while disposing a floating session');
        }),
      );
      if (!entry.completion.isCompleted) {
        entry.completion.complete();
      }
    }
    _sessions.clear();
    _floatingOrder.clear();
    _presentationOrder.clear();
    for (final pending in _pendingReopens.values) {
      pending.completeSuperseded();
    }
    _pendingReopens.clear();
    for (final pending in _pendingProjectionOpens.values) {
      pending.completeSuperseded();
    }
    _pendingProjectionOpens.clear();
    _dockController.dispose();
    super.dispose();
  }
}

final class _EntryActions implements FloatingSessionActions {
  const _EntryActions(this.host, this.entry);

  final _FloatingWorkspaceHostState host;
  final _SessionEntry entry;

  @override
  Future<void> float() => host._float(entry);

  @override
  Future<void> restart() => host._restart(entry);

  @override
  Future<void> close([Object? result]) => host._closeEntry(entry, result);
}

final class _SessionEntry {
  _SessionEntry(this.request);

  final FloatingSessionRequest request;
  final repaintBoundaryKey = GlobalKey();
  final completion = Completer<Object?>();
  FloatingSessionVisibility visibility = FloatingSessionVisibility.foreground;
  FloatingSnapshot? snapshot;
  bool initialPresentationPending = false;
  bool initialPresentationCancelled = false;
  final initialPresentationCancellation = Completer<void>();
  FloatingSessionLaunchOrigin? reverseLaunchOrigin;
  Future<void>? initialPresentationFuture;
  Future<void>? floatFuture;
  Future<void>? restoreFuture;
  Future<void>? closeFuture;
}

final class _PendingProjectionOpen {
  _PendingProjectionOpen(this.request);

  final FloatingSessionRequest request;
  final completion = Completer<Object?>();

  void completeSuperseded() {
    if (!completion.isCompleted) completion.complete();
  }

  void completeError(Object error) {
    if (!completion.isCompleted) completion.completeError(error);
  }

  void completeWith(Future<Object?> result) {
    if (!completion.isCompleted) completion.complete(result);
  }
}

final class _PendingReopen {
  _PendingReopen(this.request);

  final FloatingSessionRequest request;
  final completion = Completer<Object?>();

  void completeSuperseded() {
    if (!completion.isCompleted) completion.complete();
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (!completion.isCompleted) completion.completeError(error, stackTrace);
  }

  void completeWith(Future<Object?> result) {
    if (!completion.isCompleted) completion.complete(result);
  }
}

enum _SessionProjectionKind { opening, floating, restoring }

final class _SessionProjection {
  const _SessionProjection({
    required this.entry,
    required this.snapshot,
    required this.startRect,
    required this.endRect,
    required this.kind,
    required this.reducedMotion,
  });

  final _SessionEntry entry;
  final FloatingSnapshot snapshot;
  final Rect startRect;
  final Rect endRect;
  final _SessionProjectionKind kind;
  final bool reducedMotion;
}

final class _CloseProjection {
  const _CloseProjection({
    required this.snapshot,
    required this.logicalSize,
    required this.reducedMotion,
    required this.targetRect,
  });

  final FloatingSnapshot snapshot;
  final Size logicalSize;
  final bool reducedMotion;
  final Rect? targetRect;
}
