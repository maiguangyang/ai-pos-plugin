import 'dart:async';

import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:ai_pos_plugin_runtime/ai_pos_plugin_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AiPosPluginRegistry registry;
  late _Context context;

  setUp(() {
    registry = AiPosPluginRegistry(
      apiVersion: const AiPosPluginApiVersion(major: 0, minor: 3),
    );
    context = _Context();
  });

  test('lifecycle timeouts must be positive', () {
    expect(
      () => AiPosPluginRegistry(
        apiVersion: const AiPosPluginApiVersion(major: 0, minor: 3),
        lifecyclePolicy: const AiPosPluginLifecyclePolicy(
          initializationTimeout: Duration.zero,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => AiPosPluginRegistry(
        apiVersion: const AiPosPluginApiVersion(major: 0, minor: 3),
        lifecyclePolicy: const AiPosPluginLifecyclePolicy(
          disposalTimeout: Duration(microseconds: -1),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('closed registry rejects registration', () async {
    await registry.disposeAll();
    final plugin = _Plugin();

    await expectLater(
      registry.register(plugin, context),
      throwsA(
        isA<AiPosPluginException>().having(
          (error) => error.code,
          'code',
          AiPosPluginErrorCode.registryClosed,
        ),
      ),
    );

    expect(plugin.initializeCount, 0);
  });

  test(
    'concurrent disposeAll calls share one future and one cleanup',
    () async {
      final disposalGate = Completer<void>();
      final plugin = _Plugin(disposalGate: disposalGate.future);
      await registry.register(plugin, context);

      final first = registry.disposeAll();
      final second = registry.disposeAll();

      expect(second, same(first));
      disposalGate.complete();
      expect(await first, isEmpty);
      expect(plugin.disposeCount, 1);
    },
  );

  test('a valid plugin initializes once and becomes addressable', () async {
    final plugin = _Plugin();

    await registry.register(plugin, context);

    expect(plugin.initializeCount, 1);
    expect(registry.plugin(plugin.manifest.id), same(plugin));
    expect(registry.plugins, [same(plugin)]);
  });

  test('pageBuilder returns the declared page builder', () async {
    final plugin = _Plugin();
    await registry.register(plugin, context);

    expect(
      registry.pageBuilder('com.vendor.delivery', '/orders'),
      same(plugin.pages['/orders']),
    );
  });

  test('duplicate IDs fail before initializing the duplicate', () async {
    final first = _Plugin();
    final duplicate = _Plugin();
    await registry.register(first, context);

    await expectLater(
      registry.register(duplicate, context),
      throwsA(
        isA<AiPosPluginException>()
            .having(
              (error) => error.code,
              'code',
              AiPosPluginErrorCode.duplicatePluginId,
            )
            .having(
              (error) => error.pluginId,
              'pluginId',
              'com.vendor.delivery',
            )
            .having((error) => error.pluginVersion, 'pluginVersion', '1.0.0'),
      ),
    );
    expect(duplicate.initializeCount, 0);
  });

  test('concurrent duplicate IDs fail while the first initializes', () async {
    final initialization = Completer<void>();
    final first = _Plugin(initializationGate: initialization.future);
    final duplicate = _Plugin();

    final firstRegistration = registry.register(first, context);

    await expectLater(
      registry.register(duplicate, context),
      throwsA(
        isA<AiPosPluginException>().having(
          (error) => error.code,
          'code',
          AiPosPluginErrorCode.duplicatePluginId,
        ),
      ),
    );
    initialization.complete();
    await firstRegistration;

    expect(first.initializeCount, 1);
    expect(duplicate.initializeCount, 0);
    expect(registry.plugin(first.manifest.id), same(first));
  });

  test('an incompatible API version fails', () async {
    final plugin = _Plugin(
      requiredApiVersion: const AiPosPluginApiVersion(major: 0, minor: 4),
    );

    await expectLater(
      registry.register(plugin, context),
      throwsA(
        isA<AiPosPluginException>().having(
          (error) => error.code,
          'code',
          AiPosPluginErrorCode.incompatibleApiVersion,
        ),
      ),
    );
  });

  test('a missing granted capability fails', () async {
    final plugin = _Plugin(capabilities: const {AiPosCapability.currentStore});

    await expectLater(
      registry.register(plugin, context),
      throwsA(
        isA<AiPosPluginException>()
            .having(
              (error) => error.code,
              'code',
              AiPosPluginErrorCode.capabilityDenied,
            )
            .having(
              (error) => error.pluginId,
              'pluginId',
              'com.vendor.delivery',
            )
            .having((error) => error.pluginVersion, 'pluginVersion', '1.0.0'),
      ),
    );
  });

  test('contract validator issues fail as invalidManifest', () async {
    final plugin = _Plugin(id: 'delivery');

    await expectLater(
      registry.register(plugin, context),
      throwsA(
        isA<AiPosPluginException>().having(
          (error) => error.code,
          'code',
          AiPosPluginErrorCode.invalidManifest,
        ),
      ),
    );
    expect(plugin.initializeCount, 0);
  });

  test(
    'throwing contract getters become stable invalidManifest errors',
    () async {
      for (final plugin in [
        _ThrowingContractPlugin(throwManifest: true),
        _ThrowingContractPlugin(throwPages: true),
      ]) {
        final error = await _captureRegistrationError(
          registry,
          plugin,
          context,
        );

        expect(error.code, AiPosPluginErrorCode.invalidManifest);
        expect(error.toString(), isNot(contains('private-contract-value')));
      }
      expect(registry.plugins, isEmpty);
    },
  );

  test('initialization failure is safe and does not register plugin', () async {
    final plugin = _Plugin(initializeError: StateError('secret-token-value'));

    final error = await _captureRegistrationError(registry, plugin, context);

    expect(error.code, AiPosPluginErrorCode.initializationFailed);
    expect(error.relatedCode, isNull);
    expect(error.toString(), isNot(contains('secret-token-value')));
    expect(registry.plugins, isEmpty);
    expect(
      () => registry.plugin(plugin.manifest.id),
      throwsA(
        isA<AiPosPluginException>().having(
          (value) => value.code,
          'code',
          AiPosPluginErrorCode.pluginNotFound,
        ),
      ),
    );
  });

  test(
    'initialization failure disposes partially allocated resources',
    () async {
      final plugin = _Plugin(
        allocateResources: true,
        initializeError: StateError('resource-secret'),
      );

      final error = await _captureRegistrationError(registry, plugin, context);

      expect(error.code, AiPosPluginErrorCode.initializationFailed);
      expect(plugin.disposeCount, 1);
      expect(plugin.timer?.isActive, isFalse);
      expect(plugin.subscriptionCancelled, isTrue);
      expect(plugin.controller?.isClosed, isTrue);
      expect(registry.plugins, isEmpty);
      expect(error.toString(), isNot(contains('resource-secret')));
    },
  );

  test(
    'initialization error keeps cleanup failure as a stable related code',
    () async {
      final plugin = _Plugin(
        initializeError: StateError('initialization-secret'),
        disposeError: StateError('cleanup-secret'),
      );

      final error = await _captureRegistrationError(registry, plugin, context);

      expect(error.code, AiPosPluginErrorCode.initializationFailed);
      expect(error.relatedCode, AiPosPluginErrorCode.disposalFailed);
      expect(error.toString(), isNot(contains('initialization-secret')));
      expect(error.toString(), isNot(contains('cleanup-secret')));
    },
  );

  test('failure of a second plugin leaves the first available', () async {
    final first = _Plugin(id: 'com.vendor.first');
    final second = _Plugin(
      id: 'com.vendor.second',
      initializeError: Exception('failed'),
    );
    await registry.register(first, context);

    await expectLater(registry.register(second, context), throwsA(anything));

    expect(registry.plugin(first.manifest.id), same(first));
    expect(registry.plugins, [same(first)]);
  });

  test('missing pages produce a stable pageNotFound error', () async {
    final plugin = _Plugin();
    await registry.register(plugin, context);

    expect(
      () => registry.pageBuilder(plugin.manifest.id, '/missing'),
      throwsA(
        isA<AiPosPluginException>().having(
          (error) => error.code,
          'code',
          AiPosPluginErrorCode.pageNotFound,
        ),
      ),
    );
  });

  test(
    'disposeAll uses reverse order, continues after errors, and clears',
    () async {
      final order = <String>[];
      final first = _Plugin(id: 'com.vendor.first', disposalOrder: order);
      final second = _Plugin(
        id: 'com.vendor.second',
        disposalOrder: order,
        disposeError: StateError('private-disposal-detail'),
      );
      final third = _Plugin(id: 'com.vendor.third', disposalOrder: order);
      await registry.register(first, context);
      await registry.register(second, context);
      await registry.register(third, context);

      final errors = await registry.disposeAll();

      expect(order, [
        'com.vendor.third',
        'com.vendor.second',
        'com.vendor.first',
      ]);
      expect(first.disposeCount, 1);
      expect(second.disposeCount, 1);
      expect(third.disposeCount, 1);
      expect(errors, hasLength(1));
      expect(errors.single.code, AiPosPluginErrorCode.disposalFailed);
      expect(errors.single.relatedCode, isNull);
      expect(
        errors.single.toString(),
        isNot(contains('private-disposal-detail')),
      );
      expect(registry.plugins, isEmpty);
    },
  );

  test('disposeAll cancels and disposes an in-flight registration', () async {
    final initialization = Completer<void>();
    final plugin = _Plugin(initializationGate: initialization.future);

    final registration = registry.register(plugin, context);
    final disposal = registry.disposeAll();
    await expectLater(
      registration,
      throwsA(
        isA<AiPosPluginException>().having(
          (error) => error.code,
          'code',
          AiPosPluginErrorCode.initializationCancelled,
        ),
      ),
    );
    final errors = await disposal;

    expect(errors, isEmpty);
    expect(plugin.disposeCount, 1);
    expect(plugin.observedLifecycle?.isCancellationRequested, isTrue);
    expect(registry.plugins, isEmpty);
  });

  test(
    'registration during active disposal is rejected rather than queued',
    () async {
      final disposalGate = Completer<void>();
      final disposalStarted = Completer<void>();
      final first = _Plugin(
        id: 'com.vendor.first',
        disposalGate: disposalGate.future,
        disposalStarted: disposalStarted,
      );
      final queued = _Plugin(id: 'com.vendor.queued');
      await registry.register(first, context);

      final firstDisposal = registry.disposeAll();
      await disposalStarted.future;
      final queuedRegistration = registry.register(queued, context);
      final laterDisposal = registry.disposeAll();

      await expectLater(
        queuedRegistration,
        throwsA(
          isA<AiPosPluginException>().having(
            (error) => error.code,
            'code',
            AiPosPluginErrorCode.registryClosed,
          ),
        ),
      );
      expect(laterDisposal, same(firstDisposal));
      disposalGate.complete();
      await firstDisposal;
      expect(first.disposeCount, 1);
      expect(queued.initializeCount, 0);
      expect(queued.disposeCount, 0);
      expect(registry.plugins, isEmpty);
    },
  );

  testWidgets('initialization timeout requests cancellation and cleanup', (
    tester,
  ) async {
    registry = AiPosPluginRegistry(
      apiVersion: const AiPosPluginApiVersion(major: 0, minor: 3),
      lifecyclePolicy: const AiPosPluginLifecyclePolicy(
        initializationTimeout: Duration(seconds: 1),
        disposalTimeout: Duration(seconds: 1),
      ),
    );
    final never = Completer<void>();
    final plugin = _Plugin(initializationGate: never.future);

    final registration = registry.register(plugin, context);
    final expectation = expectLater(
      registration,
      throwsA(
        isA<AiPosPluginException>().having(
          (error) => error.code,
          'code',
          AiPosPluginErrorCode.initializationTimedOut,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await expectation;
    expect(plugin.observedLifecycle?.isCancellationRequested, isTrue);
    expect(plugin.disposeCount, 1);
    expect(registry.plugins, isEmpty);
  });

  test(
    'cooperative initialization releases context after cancellation',
    () async {
      final plugin = _Plugin(waitForCancellation: true);

      final registration = registry.register(plugin, context);
      final disposal = registry.disposeAll();

      await expectLater(registration, throwsA(isA<AiPosPluginException>()));
      await disposal;
      expect(plugin.heldContext, isNull);
      expect(plugin.disposeCount, 1);
    },
  );

  testWidgets('a disposal timeout does not block remaining plugins', (
    tester,
  ) async {
    registry = AiPosPluginRegistry(
      apiVersion: const AiPosPluginApiVersion(major: 0, minor: 3),
      lifecyclePolicy: const AiPosPluginLifecyclePolicy(
        initializationTimeout: Duration(seconds: 1),
        disposalTimeout: Duration(seconds: 1),
      ),
    );
    final order = <String>[];
    final never = Completer<void>();
    final first = _Plugin(id: 'com.vendor.first', disposalOrder: order);
    final middle = _Plugin(
      id: 'com.vendor.middle',
      disposalOrder: order,
      disposalGate: never.future,
    );
    final last = _Plugin(id: 'com.vendor.last', disposalOrder: order);
    await registry.register(first, context);
    await registry.register(middle, context);
    await registry.register(last, context);

    final disposal = registry.disposeAll();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    final errors = await disposal;

    expect(order, ['com.vendor.last', 'com.vendor.middle', 'com.vendor.first']);
    expect(errors, hasLength(1));
    expect(errors.single.code, AiPosPluginErrorCode.disposalTimedOut);
    expect(errors.single.pluginId, 'com.vendor.middle');
    expect(first.disposeCount, 1);
    expect(middle.disposeCount, 1);
    expect(last.disposeCount, 1);
    expect(registry.plugins, isEmpty);
    expect(registry.disposeAll(), same(disposal));
  });
}

Future<AiPosPluginException> _captureRegistrationError(
  AiPosPluginRegistry registry,
  AiPosPlugin plugin,
  AiPosPluginContext context,
) async {
  try {
    await registry.register(plugin, context);
  } on AiPosPluginException catch (error) {
    return error;
  }
  throw StateError('Expected registration to fail.');
}

final class _Context implements AiPosPluginContext {
  @override
  Set<AiPosCapability> get grantedCapabilities => const {};

  @override
  Locale get locale => const Locale('en');
}

final class _ThrowingContractPlugin implements AiPosPlugin {
  _ThrowingContractPlugin({
    this.throwManifest = false,
    this.throwPages = false,
  });

  final bool throwManifest;
  final bool throwPages;

  @override
  AiPosPluginManifest get manifest {
    if (throwManifest) {
      throw StateError('private-contract-value');
    }
    return AiPosPluginManifest(
      id: 'com.vendor.throwing',
      name: 'Throwing',
      version: '1.0.0',
      requiredApiVersion: const AiPosPluginApiVersion(major: 0, minor: 3),
      entryPage: '/home',
      capabilities: const {},
    );
  }

  @override
  Map<String, AiPosPluginPageBuilder> get pages {
    if (throwPages) {
      throw StateError('private-contract-value');
    }
    return {'/home': (_, _) => const SizedBox.shrink()};
  }

  @override
  Future<void> initialize(
    AiPosPluginContext context,
    AiPosPluginLifecycle lifecycle,
  ) async {}

  @override
  Future<void> dispose() async {}
}

final class _Plugin implements AiPosPlugin {
  _Plugin({
    this.id = 'com.vendor.delivery',
    this.requiredApiVersion = const AiPosPluginApiVersion(major: 0, minor: 3),
    this.capabilities = const {},
    this.initializeError,
    this.disposeError,
    this.disposalOrder,
    this.initializationGate,
    this.disposalGate,
    this.disposalStarted,
    this.allocateResources = false,
    this.waitForCancellation = false,
  });

  final String id;
  final AiPosPluginApiVersion requiredApiVersion;
  final Set<AiPosCapability> capabilities;
  final Object? initializeError;
  final Object? disposeError;
  final List<String>? disposalOrder;
  final Future<void>? initializationGate;
  final Future<void>? disposalGate;
  final Completer<void>? disposalStarted;
  final bool allocateResources;
  final bool waitForCancellation;
  int initializeCount = 0;
  int disposeCount = 0;
  Timer? timer;
  StreamController<int>? controller;
  StreamSubscription<int>? subscription;
  bool subscriptionCancelled = false;
  AiPosPluginLifecycle? observedLifecycle;
  AiPosPluginContext? heldContext;

  @override
  AiPosPluginManifest get manifest => AiPosPluginManifest(
    id: id,
    name: 'Delivery',
    version: '1.0.0',
    requiredApiVersion: requiredApiVersion,
    entryPage: '/orders',
    capabilities: capabilities,
  );

  @override
  late final Map<String, AiPosPluginPageBuilder> pages = {
    '/orders': (_, _) => const SizedBox.shrink(),
  };

  @override
  Future<void> initialize(
    AiPosPluginContext context,
    AiPosPluginLifecycle lifecycle,
  ) async {
    initializeCount += 1;
    observedLifecycle = lifecycle;
    heldContext = context;
    if (allocateResources) {
      timer = Timer.periodic(const Duration(days: 1), (_) {});
      controller = StreamController<int>();
      subscription = controller!.stream.listen((_) {});
    }
    try {
      if (waitForCancellation) {
        await lifecycle.cancellationRequested;
        lifecycle.throwIfCancellationRequested();
      }
      await initializationGate;
      if (initializeError case final error?) {
        throw error;
      }
    } finally {
      heldContext = null;
    }
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    disposalOrder?.add(id);
    disposalStarted?.complete();
    await disposalGate;
    try {
      if (disposeError case final error?) {
        throw error;
      }
    } finally {
      timer?.cancel();
      await subscription?.cancel();
      subscriptionCancelled = subscription != null;
      await controller?.close();
    }
  }
}
