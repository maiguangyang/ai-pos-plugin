import 'dart:async';

import 'package:flutter/widgets.dart';

enum FloatingSessionVisibility { foreground, floating, closing }

enum FloatingSessionSwitchDirection { left, right }

enum FloatingSessionSwitchOutcome { completed, cancelled }

abstract interface class FloatingSessionSwitchHandle {
  double get progress;

  void updateProgress(double value);

  Future<FloatingSessionSwitchOutcome> settle({required double velocityX});

  Future<void> cancel();
}

@immutable
final class FloatingSessionKey {
  const FloatingSessionKey({required this.domainId, required this.sessionId});

  final String domainId;
  final String sessionId;

  @override
  bool operator ==(Object other) {
    return other is FloatingSessionKey &&
        other.domainId == domainId &&
        other.sessionId == sessionId;
  }

  @override
  int get hashCode => Object.hash(domainId, sessionId);

  @override
  String toString() => '$domainId:$sessionId';
}

@immutable
final class FloatingDomainPolicy {
  const FloatingDomainPolicy({
    required this.domainId,
    required this.maxFloatingSessions,
    required this.maxSnapshotBytes,
  }) : assert(domainId != ''),
       assert(maxFloatingSessions > 0),
       assert(maxSnapshotBytes > 0);

  final String domainId;
  final int maxFloatingSessions;
  final int maxSnapshotBytes;
}

abstract interface class FloatingSessionActions {
  Future<void> float();
  Future<void> restart();
  Future<void> close([Object? result]);
}

/// Immutable launch geometry captured by an entry surface before a session opens.
@immutable
final class FloatingSessionLaunchOrigin {
  const FloatingSessionLaunchOrigin({
    required this.sourceRect,
    required this.viewportSize,
  });

  final Rect sourceRect;
  final Size viewportSize;
}

@immutable
final class FloatingSessionRequest {
  const FloatingSessionRequest({
    required this.key,
    required this.title,
    required this.pageBuilder,
    required this.maybePopNested,
    required this.onVisibilityChanged,
    required this.onClosed,
    this.animateInitialPresentation = false,
    this.launchOrigin,
  });

  final FloatingSessionKey key;
  final String title;
  final Widget Function(BuildContext, FloatingSessionActions) pageBuilder;
  final Future<bool> Function() maybePopNested;
  final FutureOr<void> Function(FloatingSessionVisibility visibility)
  onVisibilityChanged;
  final FutureOr<void> Function(Object? result) onClosed;

  /// Opts this request into the Host-owned initial snapshot transition.
  final bool animateInitialPresentation;

  /// Optional source geometry for an opted-in initial transition.
  final FloatingSessionLaunchOrigin? launchOrigin;
}

final class FloatingWorkspaceBusyException implements Exception {
  const FloatingWorkspaceBusyException({
    required this.requested,
    required this.foreground,
  });

  final FloatingSessionKey requested;
  final FloatingSessionKey foreground;

  @override
  String toString() {
    return 'FloatingWorkspaceBusyException(requested: $requested, '
        'foreground: $foreground)';
  }
}
