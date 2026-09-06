import 'dart:async';

import 'package:ai_pos_floating_workspace/ai_pos_floating_workspace.dart';
import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:ai_pos_plugin_runtime/ai_pos_plugin_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('maps plugin identity, visibility, completion, and restart', (
    tester,
  ) async {
    final domainController = FloatingDomainController(
      policy: AiPosPluginWorkspaceAdapter.policy,
    );
    final domainHost = _FakeDomainHost()..attach(domainController);
    final pluginController = AiPosPluginSessionHostController();
    final adapter = AiPosPluginWorkspaceAdapter(
      controller: pluginController,
      domainController: domainController,
      actionSheetPresenter: (_, _) async =>
          AiPosPluginActionSheetAction.restart,
    );
    addTearDown(() async {
      await adapter.dispose();
      domainHost.detach(domainController);
    });
    AiPosPluginPageContext? pageContext;

    final completion = pluginController.open(
      AiPosPluginSessionRequest(
        pluginId: 'inventory',
        pluginName: 'Inventory',
        pagePath: '/',
        pageBuilder: (_, context) {
          pageContext = context;
          return const ColoredBox(color: Colors.white);
        },
      ),
    );

    final mapped = domainHost.request!;
    expect(
      mapped.key,
      const FloatingSessionKey(domainId: 'plugin', sessionId: 'inventory'),
    );
    expect(AiPosPluginWorkspaceAdapter.policy.maxFloatingSessions, 5);
    expect(
      AiPosPluginWorkspaceAdapter.policy.maxSnapshotBytes,
      12 * 1024 * 1024,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => mapped.pageBuilder(context, domainHost.actions),
        ),
      ),
    );
    expect(pageContext!.visibility, AiPosPluginPageVisibility.foreground);

    await mapped.onVisibilityChanged(FloatingSessionVisibility.floating);
    expect(pageContext!.visibility, AiPosPluginPageVisibility.floating);
    await mapped.onVisibilityChanged(FloatingSessionVisibility.closing);
    expect(pageContext!.visibility, AiPosPluginPageVisibility.closing);

    await mapped.onVisibilityChanged(FloatingSessionVisibility.foreground);
    await tester.tap(find.byKey(AiPosPluginPageShell.moreButtonKey));
    await tester.pumpAndSettle();
    expect(domainHost.actions.restartCount, 1);

    domainHost.completion.complete(17);
    expect(await completion, 17);
  });

  test('dispose detaches plugin controller and closes its domain', () async {
    final domainController = FloatingDomainController(
      policy: AiPosPluginWorkspaceAdapter.policy,
    );
    final domainHost = _FakeDomainHost()..attach(domainController);
    final pluginController = AiPosPluginSessionHostController();
    final adapter = AiPosPluginWorkspaceAdapter(
      controller: pluginController,
      domainController: domainController,
    );

    await adapter.dispose();

    expect(domainHost.closeAllCount, 1);
    expect(
      () => pluginController.open(
        AiPosPluginSessionRequest(
          pluginId: 'x',
          pluginName: 'X',
          pagePath: '/',
          pageBuilder: (_, _) => const SizedBox(),
        ),
      ),
      throwsStateError,
    );
    domainHost.detach(domainController);
  });

  test('ordinary same-key restore keeps the live plugin request', () {
    final domainController = FloatingDomainController(
      policy: AiPosPluginWorkspaceAdapter.policy,
    );
    final domainHost = _FakeDomainHost()..attach(domainController);
    final pluginController = AiPosPluginSessionHostController();
    final adapter = AiPosPluginWorkspaceAdapter(
      controller: pluginController,
      domainController: domainController,
    );
    addTearDown(() async {
      await adapter.dispose();
      domainHost.detach(domainController);
    });

    unawaited(pluginController.open(_pluginRequest('Original')));
    final original = domainHost.request!;
    unawaited(pluginController.open(_pluginRequest('Ignored while live')));

    expect(domainHost.request, same(original));
  });

  test('latest same-key request is forwarded while closing', () async {
    final domainController = FloatingDomainController(
      policy: AiPosPluginWorkspaceAdapter.policy,
    );
    final domainHost = _FakeDomainHost()..attach(domainController);
    final pluginController = AiPosPluginSessionHostController();
    final adapter = AiPosPluginWorkspaceAdapter(
      controller: pluginController,
      domainController: domainController,
    );
    addTearDown(() async {
      await adapter.dispose();
      domainHost.detach(domainController);
    });

    unawaited(pluginController.open(_pluginRequest('Original')));
    await domainHost.request!.onVisibilityChanged(
      FloatingSessionVisibility.closing,
    );
    unawaited(pluginController.open(_pluginRequest('Stale reopen')));
    unawaited(pluginController.open(_pluginRequest('Latest reopen')));

    expect(domainHost.request!.title, 'Latest reopen');
  });
}

AiPosPluginSessionRequest _pluginRequest(String name) {
  return AiPosPluginSessionRequest(
    pluginId: 'inventory',
    pluginName: name,
    pagePath: '/',
    pageBuilder: (_, _) => const SizedBox(),
  );
}

final class _FakeDomainHost implements FloatingDomainHostDelegate {
  final completion = Completer<Object?>();
  final actions = _FakeActions();
  FloatingSessionRequest? request;
  int closeAllCount = 0;

  void attach(FloatingDomainController controller) =>
      controller.attachHost(this);
  void detach(FloatingDomainController controller) =>
      controller.detachHost(this);

  @override
  Future<FloatingSessionSwitchHandle?> beginInteractiveDismiss(
    FloatingDomainController controller, {
    required String foregroundSessionId,
    required bool keepForegroundAsFloating,
  }) async => null;

  @override
  Future<FloatingSessionSwitchHandle?> beginInteractiveSwitch(
    FloatingDomainController controller, {
    required String foregroundSessionId,
    required String targetSessionId,
    required FloatingSessionSwitchDirection direction,
    required bool keepForegroundAsFloating,
  }) async => null;

  @override
  Future<Object?> open(
    FloatingDomainController controller,
    FloatingSessionRequest request,
  ) {
    this.request = request;
    return completion.future;
  }

  @override
  Future<void> close(
    FloatingDomainController controller,
    String sessionId,
  ) async {}

  @override
  Future<void> closeAll(FloatingDomainController controller) async {
    closeAllCount += 1;
  }

  @override
  int sessionCount(FloatingDomainController controller) =>
      request == null ? 0 : 1;
}

final class _FakeActions implements FloatingSessionActions {
  int restartCount = 0;

  @override
  Future<void> close([Object? result]) async {}

  @override
  Future<void> float() async {}

  @override
  Future<void> restart() async {
    restartCount += 1;
  }
}
