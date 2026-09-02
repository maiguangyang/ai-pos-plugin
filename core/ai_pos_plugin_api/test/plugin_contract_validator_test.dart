import 'dart:async';

import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a namespaced id and an existing entry page', () {
    final issues = AiPosPluginContractValidator.validate(
      _Plugin(
        manifest: AiPosPluginManifest(
          id: 'com.vendor.delivery',
          name: 'Delivery',
          version: '1.0.0',
          requiredApiVersion: const AiPosPluginApiVersion(major: 0, minor: 1),
          entryPage: '/orders',
          capabilities: const {AiPosCapability.currentStore},
        ),
        pages: {'/orders': (_, _) => const SizedBox.shrink()},
      ),
    );

    expect(issues, isEmpty);
  });

  test('rejects invalid ids, versions, paths, and missing entry pages', () {
    final issues = AiPosPluginContractValidator.validate(
      _Plugin(
        manifest: AiPosPluginManifest(
          id: 'delivery',
          name: '  ',
          version: 'latest',
          requiredApiVersion: const AiPosPluginApiVersion(major: 0, minor: 1),
          entryPage: '/missing',
          capabilities: const {},
        ),
        pages: {'orders list': (_, _) => const SizedBox.shrink()},
      ),
    );

    expect(
      issues.map((issue) => issue.code),
      containsAll(<AiPosPluginContractIssueCode>{
        AiPosPluginContractIssueCode.invalidPluginId,
        AiPosPluginContractIssueCode.emptyName,
        AiPosPluginContractIssueCode.invalidPluginVersion,
        AiPosPluginContractIssueCode.invalidPagePath,
        AiPosPluginContractIssueCode.missingEntryPage,
      }),
    );
  });

  test('rejects a plugin without pages', () {
    final issues = AiPosPluginContractValidator.validate(
      _Plugin(
        manifest: AiPosPluginManifest(
          id: 'com.vendor.empty',
          name: 'Empty',
          version: '1.0.0',
          requiredApiVersion: const AiPosPluginApiVersion(major: 0, minor: 1),
          entryPage: '/home',
          capabilities: const {},
        ),
        pages: const {},
      ),
    );

    expect(
      issues.map((issue) => issue.code),
      contains(AiPosPluginContractIssueCode.emptyPages),
    );
  });

  test('manifest copies the caller-owned capability set', () {
    final source = <AiPosCapability>{AiPosCapability.currentStore};
    final manifest = AiPosPluginManifest(
      id: 'com.vendor.delivery',
      name: 'Delivery',
      version: '1.0.0',
      requiredApiVersion: const AiPosPluginApiVersion(major: 0, minor: 1),
      entryPage: '/orders',
      capabilities: source,
    );

    source.add(AiPosCapability.location);

    expect(manifest.capabilities, {AiPosCapability.currentStore});
    expect(
      () => manifest.capabilities.add(AiPosCapability.location),
      throwsUnsupportedError,
    );
  });

  test('cancellation exception has a stable non-sensitive display', () {
    const error = AiPosPluginCancellationException();

    expect(error.toString(), 'AiPosPluginCancellationException');
  });

  test('consumers can implement the lifecycle cancellation contract', () async {
    final lifecycle = _Lifecycle();

    lifecycle.cancel();

    await lifecycle.cancellationRequested;
    expect(lifecycle.isCancellationRequested, isTrue);
    expect(
      lifecycle.throwIfCancellationRequested,
      throwsA(isA<AiPosPluginCancellationException>()),
    );
  });
}

final class _Lifecycle implements AiPosPluginLifecycle {
  final Completer<void> _cancellation = Completer<void>();

  @override
  bool get isCancellationRequested => _cancellation.isCompleted;

  @override
  Future<void> get cancellationRequested => _cancellation.future;

  void cancel() {
    if (!_cancellation.isCompleted) {
      _cancellation.complete();
    }
  }

  @override
  void throwIfCancellationRequested() {
    if (isCancellationRequested) {
      throw const AiPosPluginCancellationException();
    }
  }
}

final class _Plugin implements AiPosPlugin {
  _Plugin({required this.manifest, required this.pages});

  @override
  final AiPosPluginManifest manifest;

  @override
  final Map<String, AiPosPluginPageBuilder> pages;

  @override
  Future<void> initialize(
    AiPosPluginContext context,
    AiPosPluginLifecycle lifecycle,
  ) async {}

  @override
  Future<void> dispose() async {}
}
