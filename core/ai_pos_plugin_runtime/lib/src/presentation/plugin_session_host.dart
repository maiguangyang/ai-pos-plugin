import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'plugin_page_shell.dart';
import 'plugin_page_shell_strings.dart';
import 'plugin_floating_overlay.dart';
import 'plugin_motion_policy.dart';
import 'plugin_session_host_controller.dart';
import 'plugin_session_request.dart';
import 'plugin_snapshot.dart';

typedef AiPosPluginSnapshotCapture =
    Future<AiPosPluginSnapshot> Function(
      RenderRepaintBoundary boundary,
      double pixelRatio,
    );

/// Root host for live plugin page sessions and their in-memory snapshots.
final class AiPosPluginSessionHost extends StatefulWidget {
  const AiPosPluginSessionHost({
    super.key,
    required this.controller,
    required this.child,
    this.strings = const AiPosPluginPageShellStrings(floatingLabel: 'Float'),
    this.actionSheetPresenter,
    this.maxFloatingSessions = 5,
    this.snapshotPhysicalWidth = 480,
    this.maxSnapshotBytes = 12 * 1024 * 1024,
    this.snapshotCapture = _captureSnapshot,
    this.snapshotCaptureTimeout = const Duration(seconds: 3),
    this.onSnapshotCaptureFailed,
    this.motionPolicy,
    this.backButtonDispatcher,
  }) : assert(maxFloatingSessions > 0),
       assert(snapshotPhysicalWidth > 0),
       assert(maxSnapshotBytes > 0),
       assert(snapshotCaptureTimeout > Duration.zero);

  static const dockKey = Key('ai-pos-plugin-floating-dock');
  static const scrimKey = AiPosPluginFloatingOverlay.scrimKey;
  static const closeProjectionKey = Key('ai-pos-plugin-close-projection');
  static const closeProjectionOpacityKey = Key(
    'ai-pos-plugin-close-projection-opacity',
  );
  static const closeProjectionTransformKey = Key(
    'ai-pos-plugin-close-projection-transform',
  );
  static const closeLiveTransformKey = Key(
    'ai-pos-plugin-close-live-transform',
  );
  static const floatProjectionKey = Key('ai-pos-plugin-float-projection');
  static const floatProjectionSurfaceKey = Key(
    'ai-pos-plugin-float-projection-surface',
  );
  static const restoreProjectionKey = Key('ai-pos-plugin-restore-projection');
  static const restoreProjectionSurfaceKey = Key(
    'ai-pos-plugin-restore-projection-surface',
  );

  static Key foregroundSessionKey(String pluginId) =>
      ValueKey<String>('ai-pos-plugin-foreground-$pluginId');

  static Key cardKey(String pluginId) =>
      AiPosPluginFloatingOverlay.cardKey(pluginId);

  static Key cardCloseKey(String pluginId) =>
      AiPosPluginFloatingOverlay.cardCloseKey(pluginId);

  final AiPosPluginSessionHostController controller;
  final Widget child;
  final AiPosPluginPageShellStrings strings;
  final AiPosPluginActionSheetPresenter? actionSheetPresenter;
  final int maxFloatingSessions;
  final int snapshotPhysicalWidth;
  final int maxSnapshotBytes;
  final AiPosPluginSnapshotCapture snapshotCapture;
  final Duration snapshotCaptureTimeout;
  final VoidCallback? onSnapshotCaptureFailed;
  final AiPosPluginMotionPolicy? motionPolicy;
  final BackButtonDispatcher? backButtonDispatcher;

  static Future<AiPosPluginSnapshot> _captureSnapshot(
    RenderRepaintBoundary boundary,
    double pixelRatio,
  ) async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    return AiPosPluginSnapshot.image(image);
  }

  @override
  State<AiPosPluginSessionHost> createState() => _AiPosPluginSessionHostState();
}

final class _AiPosPluginSessionHostState extends State<AiPosPluginSessionHost>
    with TickerProviderStateMixin, WidgetsBindingObserver
    implements AiPosPluginSessionHostDelegate {
  final LinkedHashMap<String, _PluginSessionEntry> _sessions =
      LinkedHashMap<String, _PluginSessionEntry>();
  final List<String> _floatingOrder = [];
  String? _foregroundPluginId;
  Future<void>? _closeAllFuture;
  late final AnimationController _closeAnimation;
  late final AnimationController _projectionAnimation;
  Future<void>? _activeProjection;
  _PluginSessionEntry? _animatedClosingEntry;
  _CloseProjection? _closeProjection;
  _SessionProjection? _sessionProjection;
  final Set<AiPosPluginSnapshot> _pendingSnapshotDisposals = {};
  int _openRevision = 0;
  double _dockVerticalFraction = 0.5;
  bool _isDisposed = false;
  final _floatingOverlayController = AiPosPluginFloatingOverlayController();
  ChildBackButtonDispatcher? _childBackButtonDispatcher;
  late final ValueGetter<Future<bool>> _systemBackCallback;

  @override
  void initState() {
    super.initState();
    _closeAnimation = AnimationController(vsync: this);
    _projectionAnimation = AnimationController(vsync: this);
    _systemBackCallback = _handleSystemBack;
    _floatingOverlayController.addListener(_onFloatingOverlayChanged);
    WidgetsBinding.instance.addObserver(this);
    _attachBackButtonDispatcher(widget.backButtonDispatcher);
    widget.controller.attachHost(this);
  }

  @override
  void didUpdateWidget(covariant AiPosPluginSessionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.detachHost(this);
      widget.controller.attachHost(this);
    }
    if (!identical(
      oldWidget.backButtonDispatcher,
      widget.backButtonDispatcher,
    )) {
      _attachBackButtonDispatcher(widget.backButtonDispatcher);
    }
  }

  void _attachBackButtonDispatcher(BackButtonDispatcher? dispatcher) {
    _childBackButtonDispatcher?.removeCallback(_systemBackCallback);
    _childBackButtonDispatcher = null;
    if (dispatcher == null) {
      return;
    }
    final child = dispatcher.createChildBackButtonDispatcher()
      ..addCallback(_systemBackCallback);
    _childBackButtonDispatcher = child;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_childBackButtonDispatcher, child)) {
        child.takePriority();
      }
    });
  }

  void _onFloatingOverlayChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) {
      return;
    }
    final isActive = state == AppLifecycleState.resumed;
    _floatingOverlayController.setApplicationActive(isActive);
    if (isActive) {
      return;
    }
    if (_projectionAnimation.isAnimating) {
      final projection = _sessionProjection;
      final completeTransition =
          projection != null &&
          _sessionProjectionProgress(projection, _projectionAnimation.value) >=
              0.5;
      _projectionAnimation.stop(canceled: true);
      if (projection != null) {
        _settleSessionProjection(
          projection,
          completeTransition: completeTransition,
        );
      }
    }
    if (_closeAnimation.isAnimating) {
      _closeAnimation.stop(canceled: false);
    }
  }

  void _settleSessionProjection(
    _SessionProjection projection, {
    required bool completeTransition,
  }) {
    if (!identical(_sessionProjection, projection)) {
      return;
    }
    final entry = projection.entry;
    AiPosPluginSnapshot? snapshotToDisposeAfterFrame;
    _sessionProjection = null;
    if (projection.kind == _SessionProjectionKind.restoring &&
        entry.restoreRevision != _openRevision &&
        entry.closeWhenRestoreSuperseded) {
      unawaited(_closeEntry(entry, null));
      return;
    }
    switch (projection.kind) {
      case _SessionProjectionKind.floating:
        if (completeTransition) {
          entry.phase = _PluginSessionPhase.floating;
          _foregroundPluginId = null;
          if (!_floatingOrder.contains(entry.request.pluginId)) {
            _floatingOrder.add(entry.request.pluginId);
          }
          _evictOverflow();
        } else {
          entry.phase = _PluginSessionPhase.foreground;
          entry.visibility.value = AiPosPluginPageVisibility.foreground;
          _foregroundPluginId = entry.request.pluginId;
          _floatingOrder.remove(entry.request.pluginId);
          entry.snapshot = null;
          snapshotToDisposeAfterFrame = projection.snapshot;
        }
      case _SessionProjectionKind.restoring:
        if (completeTransition && entry.restoreRevision == _openRevision) {
          entry.phase = _PluginSessionPhase.foreground;
          entry.visibility.value = AiPosPluginPageVisibility.foreground;
          _foregroundPluginId = entry.request.pluginId;
          entry.snapshot = null;
          snapshotToDisposeAfterFrame = projection.snapshot;
        } else {
          entry.phase = _PluginSessionPhase.floating;
          entry.visibility.value = AiPosPluginPageVisibility.floating;
          _foregroundPluginId = null;
          if (!_floatingOrder.contains(entry.request.pluginId)) {
            final index = math.min(
              projection.floatingIndex ?? _floatingOrder.length,
              _floatingOrder.length,
            );
            _floatingOrder.insert(index, entry.request.pluginId);
          }
        }
    }
    if (mounted) {
      setState(() {});
    }
    if (snapshotToDisposeAfterFrame != null) {
      _disposeSnapshotAfterFrame(snapshotToDisposeAfterFrame);
    }
  }

  double _sessionProjectionProgress(
    _SessionProjection projection,
    double rawProgress,
  ) {
    if (projection.reducedMotion) {
      return rawProgress;
    }
    return switch (projection.kind) {
      _SessionProjectionKind.floating => Curves.easeInOutCubic.transform(
        rawProgress,
      ),
      _SessionProjectionKind.restoring => Curves.easeOutCubic.transform(
        rawProgress,
      ),
    };
  }

  bool get _hasSystemBackTarget =>
      _sessionProjection != null ||
      (_floatingOrder.isNotEmpty && _floatingOverlayController.isExpanded) ||
      _foregroundEntry != null;

  Future<bool> _handleSystemBack() async {
    if (_sessionProjection != null) {
      return true;
    }
    if (_floatingOverlayController.isExpanded) {
      unawaited(_floatingOverlayController.collapse());
      return true;
    }
    final entry = _foregroundEntry;
    if (entry == null) {
      return false;
    }
    if (await entry.shellController.maybePopNested()) {
      return true;
    }
    unawaited(_requestAnimatedClose(entry, null));
    return true;
  }

  @override
  Future<Object?> open(AiPosPluginSessionRequest request) {
    if (_isDisposed || !mounted) {
      throw StateError('The plugin session host is disposed.');
    }
    if (_closeAllFuture != null) {
      throw StateError('The plugin session host is closing all sessions.');
    }
    final openRevision = ++_openRevision;
    final existing = _sessions[request.pluginId];
    if (existing != null) {
      if (existing.isClosing) {
        return _openAfterClose(existing, request, openRevision);
      }
      unawaited(_restore(existing, requestRevision: openRevision));
      return existing.completion.future;
    }

    _markActiveRestoreSuperseded(close: false);
    final foreground = _foregroundEntry;
    if (foreground != null) {
      unawaited(_closeEntry(foreground, null));
    }
    final entry = _PluginSessionEntry(request);
    _sessions[request.pluginId] = entry;
    _foregroundPluginId = request.pluginId;
    setState(() {});
    return entry.completion.future;
  }

  Future<Object?> _openAfterClose(
    _PluginSessionEntry entry,
    AiPosPluginSessionRequest request,
    int openRevision,
  ) {
    final pending = entry.reopenCompletion;
    if (pending != null) {
      entry.reopenRevision = openRevision;
      entry.reopenRequest = request;
      return pending.future;
    }
    final completion = Completer<Object?>();
    entry.reopenCompletion = completion;
    entry.reopenRevision = openRevision;
    entry.reopenRequest = request;
    unawaited(
      entry.completion.future.then<void>((_) {
        entry.reopenCompletion = null;
        final shouldReopen = entry.reopenRevision == _openRevision;
        final reopenRequest = entry.reopenRequest;
        entry.reopenRevision = null;
        entry.reopenRequest = null;
        if (!mounted || _isDisposed || _closeAllFuture != null) {
          completion.complete();
          return;
        }
        if (!shouldReopen || reopenRequest == null) {
          completion.complete();
          return;
        }
        try {
          final reopened = open(reopenRequest);
          unawaited(
            reopened.then<void>(
              completion.complete,
              onError: completion.completeError,
            ),
          );
        } catch (error, stackTrace) {
          completion.completeError(error, stackTrace);
        }
      }, onError: completion.completeError),
    );
    return completion.future;
  }

  _PluginSessionEntry? get _foregroundEntry {
    final pluginId = _foregroundPluginId;
    return pluginId == null ? null : _sessions[pluginId];
  }

  Future<void> _float(_PluginSessionEntry entry) {
    final current = entry.captureFuture;
    if (current != null) {
      return current;
    }
    if (entry.phase != _PluginSessionPhase.foreground) {
      return Future<void>.value();
    }
    final operation = _enqueueProjection(() => _performFloat(entry));
    entry.captureFuture = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(entry.captureFuture, operation)) {
          entry.captureFuture = null;
        }
      }),
    );
    return operation;
  }

  Future<void> _performFloat(_PluginSessionEntry entry) async {
    if (!_isCurrent(entry, _PluginSessionPhase.foreground)) {
      return;
    }
    final logicalSize = MediaQuery.sizeOf(context);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    entry.phase = _PluginSessionPhase.capturing;
    if (mounted) {
      setState(() {});
    }
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!_isCurrent(entry, _PluginSessionPhase.capturing)) {
        return;
      }
      final boundary = entry.repaintBoundaryKey.currentContext
          ?.findRenderObject();
      if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
        throw StateError('The plugin page is not ready for snapshot capture.');
      }
      final ratio = _capturePixelRatio(boundary.size);
      final snapshot = await _captureSnapshotWithinTimeout(boundary, ratio);
      if (snapshot == null) {
        if (_isCurrent(entry, _PluginSessionPhase.capturing)) {
          entry.phase = _PluginSessionPhase.foreground;
          if (mounted) {
            setState(() {});
          }
        }
        return;
      }
      if (!_isCurrent(entry, _PluginSessionPhase.capturing)) {
        _disposeSnapshot(snapshot);
        return;
      }
      if (snapshot.width > widget.snapshotPhysicalWidth ||
          snapshot.estimatedBytes > widget.maxSnapshotBytes) {
        _disposeSnapshot(snapshot);
        entry.phase = _PluginSessionPhase.foreground;
        if (mounted) {
          setState(() {});
        }
        _notifySnapshotCaptureFailed();
        return;
      }

      entry.snapshot = snapshot;
      entry.phase = _PluginSessionPhase.floatingProjection;
      entry.visibility.value = AiPosPluginPageVisibility.floating;
      _foregroundPluginId = null;
      _sessionProjection = _SessionProjection(
        entry: entry,
        snapshot: snapshot,
        startRect: Offset.zero & logicalSize,
        endRect: _dockProjectionRect(logicalSize),
        reducedMotion: reducedMotion,
        kind: _SessionProjectionKind.floating,
      );
      if (mounted) {
        setState(() {});
      }
      _projectionAnimation
        ..duration = reducedMotion
            ? const Duration(milliseconds: 120)
            : const Duration(milliseconds: 340)
        ..value = 0;
      try {
        await _projectionAnimation.forward().orCancel;
      } on TickerCanceled {
        return;
      }
      if (!_isCurrent(entry, _PluginSessionPhase.floatingProjection)) {
        return;
      }
      _sessionProjection = null;
      entry.phase = _PluginSessionPhase.floating;
      _floatingOrder.add(entry.request.pluginId);
      _evictOverflow();
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      if (_isCurrent(entry, _PluginSessionPhase.capturing)) {
        entry.phase = _PluginSessionPhase.foreground;
        if (mounted) {
          setState(() {});
        }
        _notifySnapshotCaptureFailed();
      }
    }
  }

  Future<AiPosPluginSnapshot?> _captureSnapshotWithinTimeout(
    RenderRepaintBoundary boundary,
    double pixelRatio, {
    bool notifyFailure = true,
  }) async {
    final capture =
        Future<AiPosPluginSnapshot>.sync(
          () => widget.snapshotCapture(boundary, pixelRatio),
        ).then<_SnapshotCaptureOutcome>(
          _SnapshotCaptureOutcome.success,
          onError: (Object error, StackTrace stackTrace) =>
              const _SnapshotCaptureOutcome.failure(),
        );
    final outcome = await capture.timeout(
      widget.snapshotCaptureTimeout,
      onTimeout: () => const _SnapshotCaptureOutcome.timeout(),
    );
    if (outcome.timedOut) {
      unawaited(capture.then(_disposeLateSnapshot));
    }
    if (outcome.snapshot == null && notifyFailure) {
      _notifySnapshotCaptureFailed();
    }
    return outcome.snapshot;
  }

  void _notifySnapshotCaptureFailed() {
    if (!_isDisposed) {
      widget.onSnapshotCaptureFailed?.call();
    }
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

  double _capturePixelRatio(Size logicalSize) {
    final deviceRatio = MediaQuery.devicePixelRatioOf(context);
    final widthRatio = widget.snapshotPhysicalWidth / logicalSize.width;
    final retainedBytes = _floatingOrder.fold<int>(0, (sum, pluginId) {
      return sum + (_sessions[pluginId]?.snapshot?.estimatedBytes ?? 0);
    });
    final availableBytes = math.max(4, widget.maxSnapshotBytes - retainedBytes);
    final logicalByteArea = logicalSize.width * logicalSize.height * 4;
    final budgetRatio = math.sqrt(availableBytes / logicalByteArea);
    return math.max(
      0.001,
      math.min(deviceRatio, math.min(widthRatio, budgetRatio)),
    );
  }

  void _evictOverflow() {
    while (_floatingOrder.length > widget.maxFloatingSessions ||
        _retainedSnapshotBytes > widget.maxSnapshotBytes) {
      final oldestId = _floatingOrder.first;
      final oldest = _sessions[oldestId];
      if (oldest == null) {
        _floatingOrder.removeAt(0);
        continue;
      }
      unawaited(_closeEntry(oldest, null));
    }
  }

  int get _retainedSnapshotBytes =>
      _floatingOrder.fold<int>(0, (sum, pluginId) {
        return sum + (_sessions[pluginId]?.snapshot?.estimatedBytes ?? 0);
      });

  void _disposeSnapshot(AiPosPluginSnapshot? snapshot) {
    _pendingSnapshotDisposals.remove(snapshot);
    _disposeSnapshotSafely(snapshot);
  }

  void _disposeSnapshotAfterFrame(AiPosPluginSnapshot snapshot) {
    if (!mounted) {
      _disposeSnapshot(snapshot);
      return;
    }
    if (!_pendingSnapshotDisposals.add(snapshot)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pendingSnapshotDisposals.remove(snapshot)) {
        _disposeSnapshotSafely(snapshot);
      }
    });
  }

  void _disposePendingSnapshots() {
    for (final snapshot in _pendingSnapshotDisposals.toList(growable: false)) {
      _disposeSnapshot(snapshot);
    }
  }

  static void _disposeLateSnapshot(_SnapshotCaptureOutcome outcome) {
    _disposeSnapshotSafely(outcome.snapshot);
  }

  static void _disposeSnapshotSafely(AiPosPluginSnapshot? snapshot) {
    if (snapshot == null) {
      return;
    }
    try {
      snapshot.dispose();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'ai_pos_plugin_runtime',
          context: ErrorDescription('while releasing a plugin snapshot'),
        ),
      );
    }
  }

  Future<void> _restore(
    _PluginSessionEntry entry, {
    Rect? sourceRect,
    int? requestRevision,
  }) {
    _markActiveRestoreSuperseded(close: true, except: entry);
    entry.restoreRevision = requestRevision ?? ++_openRevision;
    final current = entry.restoreFuture;
    if (current != null) {
      return current;
    }
    if (entry.phase == _PluginSessionPhase.foreground) {
      return Future<void>.value();
    }
    final operation = _enqueueProjection(
      () => _performRestore(entry, sourceRect),
    );
    entry.restoreFuture = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(entry.restoreFuture, operation)) {
          entry.restoreFuture = null;
        }
      }),
    );
    return operation;
  }

  void _markActiveRestoreSuperseded({
    required bool close,
    _PluginSessionEntry? except,
  }) {
    final projection = _sessionProjection;
    if (projection?.kind != _SessionProjectionKind.restoring ||
        identical(projection?.entry, except)) {
      return;
    }
    projection!.entry.closeWhenRestoreSuperseded = close;
  }

  Future<void> _performRestore(
    _PluginSessionEntry entry,
    Rect? sourceRect,
  ) async {
    if (!_isCurrent(entry, _PluginSessionPhase.floating)) {
      return;
    }
    final logicalSize = MediaQuery.sizeOf(context);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final capture = entry.captureFuture;
    if (capture != null) {
      await capture;
    }
    if (!_isCurrent(entry, _PluginSessionPhase.floating)) {
      return;
    }

    final snapshot = entry.snapshot;
    if (snapshot == null) {
      return;
    }
    final foreground = _foregroundEntry;
    if (foreground != null && !identical(foreground, entry)) {
      await _closeEntry(foreground, null);
    }
    if (!_isCurrent(entry, _PluginSessionPhase.floating)) {
      return;
    }
    unawaited(_floatingOverlayController.collapse());
    entry.phase = _PluginSessionPhase.restoring;
    final floatingIndex = _floatingOrder.indexOf(entry.request.pluginId);
    _floatingOrder.remove(entry.request.pluginId);
    _sessionProjection = _SessionProjection(
      entry: entry,
      snapshot: snapshot,
      startRect: sourceRect ?? _dockProjectionRect(logicalSize),
      endRect: Offset.zero & logicalSize,
      reducedMotion: reducedMotion,
      kind: _SessionProjectionKind.restoring,
      floatingIndex: floatingIndex < 0 ? null : floatingIndex,
    );
    if (mounted) {
      setState(() {});
    }
    _projectionAnimation
      ..duration = reducedMotion
          ? const Duration(milliseconds: 120)
          : const Duration(milliseconds: 360)
      ..value = 0;
    try {
      await _projectionAnimation.forward().orCancel;
    } on TickerCanceled {
      return;
    }

    if (!_isCurrent(entry, _PluginSessionPhase.restoring)) {
      return;
    }
    if (entry.restoreRevision != _openRevision) {
      if (entry.closeWhenRestoreSuperseded) {
        await _closeEntry(entry, null);
      } else {
        final projection = _sessionProjection;
        if (projection != null && identical(projection.entry, entry)) {
          _settleSessionProjection(projection, completeTransition: false);
        }
      }
      return;
    }
    entry.phase = _PluginSessionPhase.restoringLive;
    _foregroundPluginId = entry.request.pluginId;
    _sessionProjection = null;
    if (mounted) {
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!identical(entry.snapshot, snapshot)) {
      return;
    }
    entry.snapshot = null;
    _disposeSnapshot(snapshot);
    if (!_isCurrent(entry, _PluginSessionPhase.restoringLive)) {
      return;
    }
    entry.visibility.value = AiPosPluginPageVisibility.foreground;
    entry.phase = _PluginSessionPhase.foreground;
    entry.closeWhenRestoreSuperseded = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _enqueueProjection(Future<void> Function() operation) {
    final active = _activeProjection;
    final queued = active == null
        ? Future<void>.sync(operation)
        : active.then((_) => operation(), onError: (_, _) => operation());
    _activeProjection = queued;
    unawaited(
      queued.then<void>(
        (_) => _clearActiveProjection(queued),
        onError: (_, _) => _clearActiveProjection(queued),
      ),
    );
    return queued;
  }

  void _clearActiveProjection(Future<void> operation) {
    if (identical(_activeProjection, operation)) {
      _activeProjection = null;
    }
  }

  bool _isCurrent(_PluginSessionEntry entry, _PluginSessionPhase phase) {
    return mounted &&
        !_isDisposed &&
        identical(_sessions[entry.request.pluginId], entry) &&
        entry.phase == phase;
  }

  Future<void> _closeEntry(_PluginSessionEntry entry, Object? result) {
    final current = entry.closeFuture;
    if (current != null) {
      return current;
    }
    if (entry.phase == _PluginSessionPhase.closing ||
        entry.phase == _PluginSessionPhase.closed) {
      return _closeAllFuture ?? Future<void>.value();
    }
    final operation = _performCloseEntry(entry, result);
    entry.closeFuture = operation;
    return operation;
  }

  Future<void> _requestAnimatedClose(
    _PluginSessionEntry entry,
    Object? result,
  ) {
    if (entry.phase != _PluginSessionPhase.foreground) {
      return _closeEntry(entry, result);
    }
    final current = entry.animatedCloseFuture;
    if (current != null) {
      return current;
    }
    final operation = _performAnimatedClose(entry, result);
    entry.animatedCloseFuture = operation;
    return operation;
  }

  Future<void> _performAnimatedClose(
    _PluginSessionEntry entry,
    Object? result,
  ) async {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final logicalSize = MediaQuery.sizeOf(context);
    entry.phase = _PluginSessionPhase.animatingClose;
    entry.visibility.value = AiPosPluginPageVisibility.closing;
    _animatedClosingEntry = entry;
    if (mounted) {
      setState(() {});
    }

    AiPosPluginSnapshot? projectionSnapshot;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!_isCurrent(entry, _PluginSessionPhase.animatingClose)) {
        return;
      }
      final boundary = entry.repaintBoundaryKey.currentContext
          ?.findRenderObject();
      if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
        throw StateError('The plugin page is not ready for close projection.');
      }
      projectionSnapshot = await _captureSnapshotWithinTimeout(
        boundary,
        1,
        notifyFailure: false,
      );
    } catch (_) {
      projectionSnapshot = null;
    }

    if (!_isCurrent(entry, _PluginSessionPhase.animatingClose)) {
      _disposeSnapshot(projectionSnapshot);
      return;
    }
    if (projectionSnapshot != null) {
      _closeProjection = _CloseProjection(
        projectionSnapshot,
        logicalSize,
        reducedMotion,
      );
      entry.phase = _PluginSessionPhase.closingProjection;
      if (mounted) {
        setState(() {});
      }
    }

    _closeAnimation
      ..duration = reducedMotion
          ? const Duration(milliseconds: 120)
          : const Duration(milliseconds: 270)
      ..value = 0;
    try {
      await _closeAnimation.forward().orCancel;
    } on TickerCanceled {
      _disposeSnapshot(projectionSnapshot);
      return;
    }

    if (_closeProjection?.snapshot == projectionSnapshot) {
      _closeProjection = null;
      if (mounted) {
        setState(() {});
        await WidgetsBinding.instance.endOfFrame;
      }
      _disposeSnapshot(projectionSnapshot);
    }
    if (!_isCurrent(entry, _PluginSessionPhase.animatingClose) &&
        !_isCurrent(entry, _PluginSessionPhase.closingProjection)) {
      return;
    }
    _animatedClosingEntry = null;
    await _closeEntry(entry, result);
  }

  Future<void> _performCloseEntry(
    _PluginSessionEntry entry,
    Object? result,
  ) async {
    if (entry.phase == _PluginSessionPhase.closed) {
      return;
    }
    entry.phase = _PluginSessionPhase.closing;
    entry.visibility.value = AiPosPluginPageVisibility.closing;
    AiPosPluginSnapshot? interruptedCloseSnapshot;
    if (identical(_animatedClosingEntry, entry)) {
      _closeAnimation.stop(canceled: true);
      _animatedClosingEntry = null;
      interruptedCloseSnapshot = _closeProjection?.snapshot;
      _closeProjection = null;
    }
    if (identical(_sessionProjection?.entry, entry)) {
      _projectionAnimation.stop(canceled: true);
      _sessionProjection = null;
    }
    final snapshot = entry.snapshot;
    entry.snapshot = null;
    _floatingOrder.remove(entry.request.pluginId);
    if (identical(_sessions[entry.request.pluginId], entry)) {
      _sessions.remove(entry.request.pluginId);
    }
    if (_foregroundPluginId == entry.request.pluginId) {
      _foregroundPluginId = null;
    }
    if (mounted) {
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
    }
    _disposeSnapshot(snapshot);
    if (!identical(interruptedCloseSnapshot, snapshot)) {
      _disposeSnapshot(interruptedCloseSnapshot);
    }
    entry.phase = _PluginSessionPhase.closed;
    entry.visibility.dispose();
    if (!entry.completion.isCompleted) {
      entry.completion.complete(result);
    }
  }

  Future<void> _restartEntry(_PluginSessionEntry entry) async {
    if (!identical(_sessions[entry.request.pluginId], entry)) {
      return;
    }
    final restartRevision = ++_openRevision;
    final request = entry.request;
    await _requestAnimatedClose(entry, null);
    if (!mounted || _isDisposed || _closeAllFuture != null) {
      return;
    }
    if (restartRevision != _openRevision) {
      return;
    }
    if (_sessions.containsKey(request.pluginId)) {
      return;
    }
    unawaited(open(request));
  }

  @override
  Future<void> closeAll() {
    final current = _closeAllFuture;
    if (current != null) {
      return current;
    }
    late final Future<void> operation;
    operation = _performCloseAll().whenComplete(() {
      if (identical(_closeAllFuture, operation)) {
        _closeAllFuture = null;
      }
    });
    _closeAllFuture = operation;
    return operation;
  }

  Future<void> _performCloseAll() async {
    _closeAnimation.stop(canceled: true);
    _projectionAnimation.stop(canceled: true);
    _sessionProjection = null;
    final closeProjection = _closeProjection;
    _closeProjection = null;
    _animatedClosingEntry = null;
    final entries = _sessions.values.toList(growable: false);
    final snapshots = <AiPosPluginSnapshot>[];
    if (closeProjection != null) {
      snapshots.add(closeProjection.snapshot);
    }
    for (final entry in entries) {
      entry.phase = _PluginSessionPhase.closing;
      entry.visibility.value = AiPosPluginPageVisibility.closing;
      final snapshot = entry.snapshot;
      entry.snapshot = null;
      if (snapshot != null) {
        snapshots.add(snapshot);
      }
    }
    _sessions.clear();
    _floatingOrder.clear();
    _foregroundPluginId = null;
    if (mounted) {
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
    }
    _disposePendingSnapshots();
    for (final snapshot in snapshots) {
      _disposeSnapshot(snapshot);
    }
    for (final entry in entries) {
      entry.phase = _PluginSessionPhase.closed;
      entry.visibility.dispose();
      if (!entry.completion.isCompleted) {
        entry.completion.complete();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocksHostInteraction =
        _foregroundEntry != null || _sessionProjection != null;
    final content = Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: blocksHostInteraction,
          child: IgnorePointer(
            ignoring: blocksHostInteraction,
            child: widget.child,
          ),
        ),
        for (final entry in _sessions.values) _buildSession(entry),
        if (_floatingOrder.isNotEmpty)
          KeyedSubtree(
            key: AiPosPluginSessionHost.dockKey,
            child: AiPosPluginFloatingOverlay(
              controller: _floatingOverlayController,
              handleSystemBack: false,
              cards: [
                for (final pluginId in _floatingOrder)
                  _floatingCard(_sessions[pluginId]!),
              ],
              initialDockVerticalFraction: _dockVerticalFraction,
              onDockVerticalFractionChanged: (fraction) {
                _dockVerticalFraction = fraction;
              },
              dockSemanticLabel: widget.strings.floatingDockLabel,
              cardOpenSemanticLabel: widget.strings.floatingCardOpenLabel,
              cardCloseSemanticLabel: widget.strings.floatingCardCloseLabel,
              motionPolicy: widget.motionPolicy,
            ),
          ),
        if (_sessionProjection case final projection?)
          _buildSessionProjection(projection),
        if (_closeProjection case final projection?)
          _buildCloseProjection(projection),
      ],
    );
    final backAwareContent = PopScope<void>(
      canPop: !_hasSystemBackTarget,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_handleSystemBack());
        }
      },
      child: content,
    );
    return Overlay.maybeOf(context) == null
        ? Overlay.wrap(child: backAwareContent)
        : backAwareContent;
  }

  Widget _buildSession(_PluginSessionEntry entry) {
    final isPainted =
        entry.phase == _PluginSessionPhase.foreground ||
        entry.phase == _PluginSessionPhase.capturing ||
        entry.phase == _PluginSessionPhase.restoringLive ||
        entry.phase == _PluginSessionPhase.animatingClose;
    final isInteractive = entry.phase == _PluginSessionPhase.foreground;
    Widget session = Offstage(
      offstage: !isPainted,
      child: TickerMode(
        enabled: isPainted,
        child: ExcludeSemantics(
          excluding: !isInteractive,
          child: IgnorePointer(
            ignoring: !isInteractive,
            child: KeyedSubtree(
              key: entry.pageKey,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    key: entry.repaintBoundaryKey,
                    child: AiPosPluginPageShell(
                      controller: entry.shellController,
                      pluginName: entry.request.pluginName,
                      pluginDescription: entry.request.pluginDescription,
                      pageBuilder: entry.request.pageBuilder,
                      visibilityListenable: entry.visibility,
                      strings: widget.strings,
                      actionSheetPresenter: widget.actionSheetPresenter,
                      onRequestFloat: () => _float(entry),
                      onRequestRestart: () => _restartEntry(entry),
                      onRequestClose: (result) =>
                          unawaited(_requestAnimatedClose(entry, result)),
                      handleSystemBack: false,
                    ),
                  ),
                  if (isInteractive)
                    IgnorePointer(
                      child: SizedBox.expand(
                        key: AiPosPluginSessionHost.foregroundSessionKey(
                          entry.request.pluginId,
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
    if (identical(_animatedClosingEntry, entry) && _closeProjection == null) {
      session = _buildCloseTransform(
        key: AiPosPluginSessionHost.closeLiveTransformKey,
        size: MediaQuery.sizeOf(context),
        reducedMotion: MediaQuery.disableAnimationsOf(context),
        child: session,
      );
    }
    return session;
  }

  AiPosPluginFloatingCard _floatingCard(_PluginSessionEntry entry) {
    return AiPosPluginFloatingCard(
      pluginId: entry.request.pluginId,
      pluginName: entry.request.pluginName,
      snapshot: entry.snapshot!,
      onRestore: (sourceRect) =>
          unawaited(_restore(entry, sourceRect: sourceRect)),
      onClose: () => unawaited(_closeEntry(entry, null)),
    );
  }

  Widget _buildSessionProjection(_SessionProjection projection) {
    final isFloating = projection.kind == _SessionProjectionKind.floating;
    final projectionKey = isFloating
        ? AiPosPluginSessionHost.floatProjectionKey
        : AiPosPluginSessionHost.restoreProjectionKey;
    final surfaceKey = isFloating
        ? AiPosPluginSessionHost.floatProjectionSurfaceKey
        : AiPosPluginSessionHost.restoreProjectionSurfaceKey;
    return Positioned.fill(
      key: projectionKey,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _projectionAnimation,
          builder: (context, _) {
            final rawProgress = _projectionAnimation.value;
            final progress = _sessionProjectionProgress(
              projection,
              rawProgress,
            );
            final rect = projection.reducedMotion
                ? projection.endRect
                : Rect.lerp(
                    projection.startRect,
                    projection.endRect,
                    progress,
                  )!;
            final cornerRadius = projection.reducedMotion
                ? 0.0
                : 18 * (isFloating ? progress : 1 - progress);
            final opacity = projection.reducedMotion
                ? (isFloating ? 1 - rawProgress : rawProgress)
                : 1.0;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fromRect(
                  key: surfaceKey,
                  rect: rect,
                  child: Opacity(
                    opacity: opacity,
                    child: PhysicalModel(
                      color: Theme.of(context).colorScheme.surface,
                      elevation: projection.reducedMotion
                          ? 0
                          : 12 * (isFloating ? progress : 1 - progress),
                      shadowColor: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(cornerRadius),
                      clipBehavior: Clip.antiAlias,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withValues(alpha: 0.9),
                            width: projection.reducedMotion ? 0 : 2,
                          ),
                        ),
                        child: projection.snapshot.build(fit: BoxFit.fill),
                      ),
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
      key: AiPosPluginSessionHost.closeProjectionKey,
      child: _buildCloseTransform(
        key: AiPosPluginSessionHost.closeProjectionTransformKey,
        size: projection.logicalSize,
        reducedMotion: projection.reducedMotion,
        child: projection.snapshot.build(fit: BoxFit.fill),
      ),
    );
  }

  Widget _buildCloseTransform({
    required Key key,
    required Size size,
    required bool reducedMotion,
    required Widget child,
  }) {
    return AnimatedBuilder(
      animation: _closeAnimation,
      child: child,
      builder: (context, child) {
        final progress = _closeAnimation.value;
        final offset = reducedMotion
            ? Offset.zero
            : Offset(
                -0.28 * size.width * progress,
                0.55 * size.height * progress,
              );
        final scale = reducedMotion ? 1.0 : 1 - 0.92 * progress;
        final isProjection =
            key == AiPosPluginSessionHost.closeProjectionTransformKey;
        return Transform.translate(
          key: key,
          offset: offset,
          child: Transform.scale(
            alignment: Alignment.topRight,
            scale: scale,
            child: Opacity(
              key: isProjection
                  ? AiPosPluginSessionHost.closeProjectionOpacityKey
                  : null,
              opacity: 1 - progress,
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _childBackButtonDispatcher?.removeCallback(_systemBackCallback);
    _childBackButtonDispatcher = null;
    _floatingOverlayController.removeListener(_onFloatingOverlayChanged);
    widget.controller.detachHost(this);
    _closeAnimation.dispose();
    _projectionAnimation.dispose();
    _disposeSnapshot(_closeProjection?.snapshot);
    _closeProjection = null;
    _disposePendingSnapshots();
    for (final entry in _sessions.values) {
      entry.phase = _PluginSessionPhase.closed;
      _disposeSnapshot(entry.snapshot);
      entry.snapshot = null;
      entry.visibility.dispose();
      if (!entry.completion.isCompleted) {
        entry.completion.complete();
      }
    }
    _sessions.clear();
    _floatingOrder.clear();
    super.dispose();
  }
}

enum _PluginSessionPhase {
  foreground,
  capturing,
  floatingProjection,
  floating,
  restoring,
  restoringLive,
  animatingClose,
  closingProjection,
  closing,
  closed,
}

final class _PluginSessionEntry {
  _PluginSessionEntry(this.request);

  final AiPosPluginSessionRequest request;
  final pageKey = GlobalKey();
  final repaintBoundaryKey = GlobalKey();
  final shellController = AiPosPluginPageShellController();
  final visibility = ValueNotifier<AiPosPluginPageVisibility>(
    AiPosPluginPageVisibility.foreground,
  );
  final completion = Completer<Object?>();
  _PluginSessionPhase phase = _PluginSessionPhase.foreground;
  AiPosPluginSnapshot? snapshot;
  Future<void>? captureFuture;
  Future<void>? restoreFuture;
  Future<void>? closeFuture;
  Future<void>? animatedCloseFuture;
  Completer<Object?>? reopenCompletion;
  AiPosPluginSessionRequest? reopenRequest;
  int? reopenRevision;
  int? restoreRevision;
  bool closeWhenRestoreSuperseded = false;

  bool get isClosing => switch (phase) {
    _PluginSessionPhase.animatingClose ||
    _PluginSessionPhase.closingProjection ||
    _PluginSessionPhase.closing ||
    _PluginSessionPhase.closed => true,
    _ => false,
  };
}

final class _CloseProjection {
  const _CloseProjection(this.snapshot, this.logicalSize, this.reducedMotion);

  final AiPosPluginSnapshot snapshot;
  final Size logicalSize;
  final bool reducedMotion;
}

enum _SessionProjectionKind { floating, restoring }

final class _SessionProjection {
  const _SessionProjection({
    required this.entry,
    required this.snapshot,
    required this.startRect,
    required this.endRect,
    required this.reducedMotion,
    required this.kind,
    this.floatingIndex,
  });

  final _PluginSessionEntry entry;
  final AiPosPluginSnapshot snapshot;
  final Rect startRect;
  final Rect endRect;
  final bool reducedMotion;
  final _SessionProjectionKind kind;
  final int? floatingIndex;
}

final class _SnapshotCaptureOutcome {
  const _SnapshotCaptureOutcome.success(this.snapshot) : timedOut = false;
  const _SnapshotCaptureOutcome.failure() : snapshot = null, timedOut = false;
  const _SnapshotCaptureOutcome.timeout() : snapshot = null, timedOut = true;

  final AiPosPluginSnapshot? snapshot;
  final bool timedOut;
}
