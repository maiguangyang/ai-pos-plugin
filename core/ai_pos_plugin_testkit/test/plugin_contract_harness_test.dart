import 'dart:async';

import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:ai_pos_plugin_testkit/ai_pos_plugin_testkit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('page context exposes current and listenable visibility', () {
    final context = FakeAiPosPluginPageContext();
    final observed = <AiPosPluginPageVisibility>[];
    context.visibilityListenable.addListener(
      () => observed.add(context.visibilityListenable.value),
    );

    expect(context.visibility, AiPosPluginPageVisibility.foreground);
    context.setVisibility(AiPosPluginPageVisibility.floating);
    context.setVisibility(AiPosPluginPageVisibility.closing);

    expect(observed, <AiPosPluginPageVisibility>[
      AiPosPluginPageVisibility.floating,
      AiPosPluginPageVisibility.closing,
    ]);
    context.invalidate();
    expect(context.hasVisibilityListeners, isFalse);
    expect(
      () => context.setVisibility(AiPosPluginPageVisibility.foreground),
      throwsStateError,
    );
  });

  test('fake initialization context exposes immutable values', () {
    final capabilities = <AiPosCapability>{AiPosCapability.currentStore};
    final context = FakeAiPosPluginContext(
      locale: const Locale('zh', 'CN'),
      grantedCapabilities: capabilities,
    );

    capabilities.add(AiPosCapability.location);

    expect(context.locale, const Locale('zh', 'CN'));
    expect(context.grantedCapabilities, {AiPosCapability.currentStore});
    expect(
      () => context.grantedCapabilities.add(AiPosCapability.location),
      throwsUnsupportedError,
    );
  });

  test('fake page context bounds retained results and invalidates', () {
    final context = FakeAiPosPluginPageContext(maxRecordedResults: 20);
    final results = List<Object>.generate(25, (_) => Object());

    for (final result in results) {
      context.close(result: result);
    }

    expect(context.closeCount, 25);
    expect(context.closeResults, orderedEquals(results.skip(5)));
    expect(() => context.closeResults.add(Object()), throwsUnsupportedError);
    context.invalidate();
    context.close(result: Object());
    expect(context.isActive, isFalse);
    expect(context.closeCount, 25);
    expect(context.closeResults, isEmpty);

    final countOnly = FakeAiPosPluginPageContext(maxRecordedResults: 0);
    countOnly.close(result: Object());
    expect(countOnly.closeCount, 1);
    expect(countOnly.closeResults, isEmpty);
    expect(
      () => FakeAiPosPluginPageContext(maxRecordedResults: -1),
      throwsArgumentError,
    );
  });

  test('fake lifecycle cancellation is idempotent and observable', () async {
    final lifecycle = FakeAiPosPluginLifecycle();
    expect(lifecycle.isCancellationRequested, isFalse);

    lifecycle.cancel();
    lifecycle.cancel();

    await lifecycle.cancellationRequested;
    expect(lifecycle.isCancellationRequested, isTrue);
    expect(
      lifecycle.throwIfCancellationRequested,
      throwsA(isA<AiPosPluginCancellationException>()),
    );
  });

  test('lifecycle timeouts must be positive', () {
    expect(
      () => AiPosPluginContractHarness(initializationTimeout: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => AiPosPluginContractHarness(disposalTimeout: Duration.zero),
      throwsArgumentError,
    );
  });

  test('invalid contracts return issues without initialization', () async {
    final plugin = _ResourcePlugin(id: 'invalid');

    final result = await AiPosPluginContractHarness().verify(
      plugin,
      FakeAiPosPluginContext(locale: const Locale('en')),
    );

    expect(result.failureCode, AiPosPluginVerificationFailure.invalidContract);
    expect(result.issues, isNotEmpty);
    expect(plugin.initializeCount, 0);
    expect(plugin.disposeCount, 0);
  });

  test('throwing contract getters return a stable invalid result', () async {
    final result = await AiPosPluginContractHarness().verify(
      _ThrowingContractPlugin(),
      FakeAiPosPluginContext(locale: const Locale('en')),
    );

    expect(result.failureCode, AiPosPluginVerificationFailure.invalidContract);
    expect(result.toString(), isNot(contains('private-contract-value')));
  });

  test(
    'valid contracts initialize and dispose resources exactly once',
    () async {
      final plugin = _ResourcePlugin();

      final result = await AiPosPluginContractHarness().verify(
        plugin,
        FakeAiPosPluginContext(locale: const Locale('en')),
      );

      expect(result.isSuccess, isTrue);
      _expectReleased(plugin);
    },
  );

  test('initialization failure performs partial resource cleanup', () async {
    final plugin = _ResourcePlugin(
      initializeError: StateError('private-api-key'),
    );

    final result = await AiPosPluginContractHarness().verify(
      plugin,
      FakeAiPosPluginContext(locale: const Locale('en')),
    );

    expect(
      result.failureCode,
      AiPosPluginVerificationFailure.initializationFailed,
    );
    expect(result.toString(), isNot(contains('private-api-key')));
    _expectReleased(plugin);
  });

  test('initialization failure preserves a related cleanup failure', () async {
    final plugin = _ResourcePlugin(
      initializeError: StateError('private-initialize-data'),
      disposeError: StateError('private-dispose-data'),
    );

    final result = await AiPosPluginContractHarness().verify(
      plugin,
      FakeAiPosPluginContext(locale: const Locale('en')),
    );

    expect(
      result.failureCode,
      AiPosPluginVerificationFailure.initializationFailed,
    );
    expect(
      result.relatedFailureCode,
      AiPosPluginVerificationFailure.disposalFailed,
    );
    expect(result.toString(), isNot(contains('private-initialize-data')));
    expect(result.toString(), isNot(contains('private-dispose-data')));
    _expectReleased(plugin);
  });

  test('initialization timeout requests cooperative cancellation', () async {
    final plugin = _ResourcePlugin(waitForCancellation: true);
    final verification = AiPosPluginContractHarness(
      initializationTimeout: const Duration(milliseconds: 10),
    ).verify(plugin, FakeAiPosPluginContext(locale: const Locale('en')));
    final result = await verification;

    expect(
      result.failureCode,
      AiPosPluginVerificationFailure.initializationTimedOut,
    );
    expect(plugin.cancellationObserved, isTrue);
    expect(plugin.disposeCount, 1);
    expect(plugin.retainedContext, isNull);
    _expectReleased(plugin);
  });

  test('cancellation exceptions use a stable failure code', () async {
    final plugin = _ResourcePlugin(throwCancellation: true);

    final result = await AiPosPluginContractHarness().verify(
      plugin,
      FakeAiPosPluginContext(locale: const Locale('en')),
    );

    expect(
      result.failureCode,
      AiPosPluginVerificationFailure.initializationCancelled,
    );
    _expectReleased(plugin);
  });

  test('disposal failures return a stable non-sensitive result', () async {
    final plugin = _ResourcePlugin(
      disposeError: StateError('private-dispose-data'),
    );

    final result = await AiPosPluginContractHarness().verify(
      plugin,
      FakeAiPosPluginContext(locale: const Locale('en')),
    );

    expect(result.failureCode, AiPosPluginVerificationFailure.disposalFailed);
    expect(result.toString(), isNot(contains('private-dispose-data')));
    _expectReleased(plugin);
  });

  test('disposal timeout is bounded and stable', () async {
    final plugin = _ResourcePlugin(blockDisposal: true);
    final verification = AiPosPluginContractHarness(
      disposalTimeout: const Duration(milliseconds: 10),
    ).verify(plugin, FakeAiPosPluginContext(locale: const Locale('en')));
    final result = await verification;

    expect(result.failureCode, AiPosPluginVerificationFailure.disposalTimedOut);

    _expectReleased(plugin);
  });
}

void _expectReleased(_ResourcePlugin plugin) {
  expect(plugin.initializeCount, 1);
  expect(plugin.disposeCount, 1);
  expect(plugin.timer?.isActive, isFalse);
  expect(plugin.subscriptionCancelled, isTrue);
  expect(plugin.controller?.isClosed, isTrue);
  expect(plugin.notifier?.isDisposed, isTrue);
  expect(plugin.retainedContext, isNull);
}

final class _ResourcePlugin implements AiPosPlugin {
  _ResourcePlugin({
    this.id = 'com.vendor.delivery',
    this.initializeError,
    this.disposeError,
    this.waitForCancellation = false,
    this.throwCancellation = false,
    this.blockDisposal = false,
  });

  final String id;
  final Object? initializeError;
  final Object? disposeError;
  final bool waitForCancellation;
  final bool throwCancellation;
  final bool blockDisposal;
  int initializeCount = 0;
  int disposeCount = 0;
  Timer? timer;
  StreamController<int>? controller;
  StreamSubscription<int>? subscription;
  _TrackingNotifier? notifier;
  bool subscriptionCancelled = false;
  AiPosPluginContext? retainedContext;

  @override
  AiPosPluginManifest get manifest => AiPosPluginManifest(
    id: id,
    name: 'Delivery',
    version: '1.0.0',
    requiredApiVersion: const AiPosPluginApiVersion(major: 0, minor: 3),
    entryPage: '/orders',
    capabilities: const {},
  );

  @override
  Map<String, AiPosPluginPageBuilder> get pages => {
    '/orders': (_, _) => const SizedBox.shrink(),
  };

  @override
  Future<void> initialize(
    AiPosPluginContext context,
    AiPosPluginLifecycle lifecycle,
  ) async {
    initializeCount += 1;
    retainedContext = context;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {});
    controller = StreamController<int>();
    subscription = controller!.stream.listen((_) {});
    notifier = _TrackingNotifier();
    if (throwCancellation) {
      throw const AiPosPluginCancellationException();
    }
    if (initializeError case final error?) {
      throw error;
    }
    if (waitForCancellation) {
      await lifecycle.cancellationRequested;
      cancellationObserved = lifecycle.isCancellationRequested;
    }
    retainedContext = null;
  }

  bool cancellationObserved = false;

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    retainedContext = null;
    timer?.cancel();
    await subscription?.cancel();
    subscriptionCancelled = true;
    await controller?.close();
    notifier?.dispose();
    if (disposeError case final error?) {
      throw error;
    }
    if (blockDisposal) {
      await Completer<void>().future;
    }
  }
}

final class _ThrowingContractPlugin implements AiPosPlugin {
  @override
  AiPosPluginManifest get manifest =>
      throw StateError('private-contract-value');

  @override
  Map<String, AiPosPluginPageBuilder> get pages => const {};

  @override
  Future<void> initialize(
    AiPosPluginContext context,
    AiPosPluginLifecycle lifecycle,
  ) async {}

  @override
  Future<void> dispose() async {}
}

final class _TrackingNotifier extends ChangeNotifier {
  bool isDisposed = false;

  @override
  void dispose() {
    isDisposed = true;
    super.dispose();
  }
}
