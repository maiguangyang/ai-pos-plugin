import 'dart:async';

import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:flutter/foundation.dart';

import 'fake_plugin_lifecycle.dart';

/// Stable failure categories produced without retaining plugin exceptions.
enum AiPosPluginVerificationFailure {
  invalidContract,
  initializationFailed,
  initializationTimedOut,
  initializationCancelled,
  disposalFailed,
  disposalTimedOut,
}

/// Immutable result of one API-only plugin contract verification.
@immutable
final class AiPosPluginVerificationResult {
  AiPosPluginVerificationResult._({
    required this.isSuccess,
    required List<AiPosPluginContractIssue> issues,
    required this.failureCode,
    required this.relatedFailureCode,
  }) : issues = List<AiPosPluginContractIssue>.unmodifiable(issues);

  factory AiPosPluginVerificationResult.success() {
    return AiPosPluginVerificationResult._(
      isSuccess: true,
      issues: const [],
      failureCode: null,
      relatedFailureCode: null,
    );
  }

  factory AiPosPluginVerificationResult.failure(
    AiPosPluginVerificationFailure failureCode, {
    List<AiPosPluginContractIssue> issues = const [],
    AiPosPluginVerificationFailure? relatedFailureCode,
  }) {
    return AiPosPluginVerificationResult._(
      isSuccess: false,
      issues: issues,
      failureCode: failureCode,
      relatedFailureCode: relatedFailureCode,
    );
  }

  final bool isSuccess;
  final List<AiPosPluginContractIssue> issues;
  final AiPosPluginVerificationFailure? failureCode;
  final AiPosPluginVerificationFailure? relatedFailureCode;

  @override
  String toString() {
    return 'AiPosPluginVerificationResult('
        'isSuccess: $isSuccess, '
        'failureCode: ${failureCode?.name}, '
        'relatedFailureCode: ${relatedFailureCode?.name}, '
        'issueCount: ${issues.length})';
  }
}

/// Verifies public contracts and bounded lifecycle behavior without runtime.
final class AiPosPluginContractHarness {
  AiPosPluginContractHarness({
    this.initializationTimeout = const Duration(seconds: 30),
    this.disposalTimeout = const Duration(seconds: 10),
  }) {
    if (initializationTimeout <= Duration.zero ||
        disposalTimeout <= Duration.zero) {
      throw ArgumentError('Plugin lifecycle timeouts must be positive.');
    }
  }

  final Duration initializationTimeout;
  final Duration disposalTimeout;

  Future<AiPosPluginVerificationResult> verify(
    AiPosPlugin plugin,
    AiPosPluginContext context,
  ) async {
    late final List<AiPosPluginContractIssue> issues;
    try {
      issues = AiPosPluginContractValidator.validate(plugin);
    } catch (_) {
      return AiPosPluginVerificationResult.failure(
        AiPosPluginVerificationFailure.invalidContract,
      );
    }
    if (issues.isNotEmpty) {
      return AiPosPluginVerificationResult.failure(
        AiPosPluginVerificationFailure.invalidContract,
        issues: issues,
      );
    }

    final lifecycle = FakeAiPosPluginLifecycle();
    Future<AiPosPluginVerificationFailure?>? disposal;
    Future<AiPosPluginVerificationFailure?> disposeOnce() {
      return disposal ??= _dispose(plugin);
    }

    final initialization = await _initialize(plugin, context, lifecycle);
    if (initialization != null) {
      lifecycle.cancel();
      final disposalFailure = await disposeOnce();
      return AiPosPluginVerificationResult.failure(
        initialization,
        relatedFailureCode: disposalFailure,
      );
    }

    final disposalFailure = await disposeOnce();
    if (disposalFailure != null) {
      return AiPosPluginVerificationResult.failure(disposalFailure);
    }
    return AiPosPluginVerificationResult.success();
  }

  Future<AiPosPluginVerificationFailure?> _initialize(
    AiPosPlugin plugin,
    AiPosPluginContext context,
    FakeAiPosPluginLifecycle lifecycle,
  ) async {
    final timeout = Completer<_InitializationOutcome>();
    final timer = Timer(
      initializationTimeout,
      () => timeout.complete(_InitializationOutcome.timedOut),
    );
    final source =
        Future<void>.sync(
          () => plugin.initialize(context, lifecycle),
        ).then<_InitializationOutcome>(
          (_) => _InitializationOutcome.succeeded,
          onError: (Object error, StackTrace _) =>
              error is AiPosPluginCancellationException
              ? _InitializationOutcome.cancelled
              : _InitializationOutcome.failed,
        );

    final _InitializationOutcome outcome;
    try {
      outcome = await Future.any([source, timeout.future]);
    } finally {
      timer.cancel();
    }

    return switch (outcome) {
      _InitializationOutcome.succeeded => null,
      _InitializationOutcome.failed =>
        AiPosPluginVerificationFailure.initializationFailed,
      _InitializationOutcome.cancelled =>
        AiPosPluginVerificationFailure.initializationCancelled,
      _InitializationOutcome.timedOut =>
        AiPosPluginVerificationFailure.initializationTimedOut,
    };
  }

  Future<AiPosPluginVerificationFailure?> _dispose(AiPosPlugin plugin) async {
    final timeout = Completer<_DisposalOutcome>();
    final timer = Timer(
      disposalTimeout,
      () => timeout.complete(_DisposalOutcome.timedOut),
    );
    final source = Future<void>.sync(plugin.dispose).then<_DisposalOutcome>(
      (_) => _DisposalOutcome.succeeded,
      onError: (Object _, StackTrace _) => _DisposalOutcome.failed,
    );

    final _DisposalOutcome outcome;
    try {
      outcome = await Future.any([source, timeout.future]);
    } finally {
      timer.cancel();
    }

    return switch (outcome) {
      _DisposalOutcome.succeeded => null,
      _DisposalOutcome.failed => AiPosPluginVerificationFailure.disposalFailed,
      _DisposalOutcome.timedOut =>
        AiPosPluginVerificationFailure.disposalTimedOut,
    };
  }
}

enum _InitializationOutcome { succeeded, failed, timedOut, cancelled }

enum _DisposalOutcome { succeeded, failed, timedOut }
