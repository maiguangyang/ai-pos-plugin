import 'dart:math' as math;

import 'package:flutter/foundation.dart';

@immutable
final class FloatingMotionPolicy {
  FloatingMotionPolicy({
    this.velocityProjectionDivisor = 4000,
    this.maximumVelocityProjection = 0.35,
    this.openThreshold = 0.5,
    this.velocityDurationDivisor = 1000,
    this.minimumSettleDuration = const Duration(milliseconds: 160),
    this.maximumSettleDuration = const Duration(milliseconds: 320),
  }) {
    if (velocityProjectionDivisor <= 0 || velocityDurationDivisor <= 0) {
      throw ArgumentError('Velocity divisors must be positive.');
    }
    if (maximumVelocityProjection < 0) {
      throw ArgumentError.value(
        maximumVelocityProjection,
        'maximumVelocityProjection',
        'must not be negative',
      );
    }
    if (openThreshold < 0 || openThreshold > 1) {
      throw ArgumentError.value(
        openThreshold,
        'openThreshold',
        'must be between zero and one',
      );
    }
    if (minimumSettleDuration > maximumSettleDuration) {
      throw ArgumentError(
        'minimumSettleDuration must not exceed maximumSettleDuration.',
      );
    }
  }

  final double velocityProjectionDivisor;
  final double maximumVelocityProjection;
  final double openThreshold;
  final double velocityDurationDivisor;
  final Duration minimumSettleDuration;
  final Duration maximumSettleDuration;

  double progressForDrag({required double dx, required double revealExtent}) {
    if (revealExtent <= 0) {
      throw ArgumentError.value(
        revealExtent,
        'revealExtent',
        'must be positive',
      );
    }
    return (-dx / revealExtent).clamp(0.0, 1.0);
  }

  double targetForRelease({
    required double progress,
    required double velocityX,
  }) {
    final boundedProgress = progress.clamp(0.0, 1.0);
    final projectedVelocity = (-velocityX / velocityProjectionDivisor).clamp(
      -maximumVelocityProjection,
      maximumVelocityProjection,
    );
    return boundedProgress + projectedVelocity >= openThreshold ? 1 : 0;
  }

  Duration settleDuration({
    required double progress,
    required double target,
    required double velocityX,
  }) {
    final remaining = (target.clamp(0.0, 1.0) - progress.clamp(0.0, 1.0)).abs();
    final normalizedSpeed = math.max(
      1.0,
      velocityX.abs() / velocityDurationDivisor,
    );
    final rawMilliseconds =
        maximumSettleDuration.inMilliseconds * remaining / normalizedSpeed;
    final boundedMilliseconds = rawMilliseconds.round().clamp(
      minimumSettleDuration.inMilliseconds,
      maximumSettleDuration.inMilliseconds,
    );
    return Duration(milliseconds: boundedMilliseconds);
  }
}
