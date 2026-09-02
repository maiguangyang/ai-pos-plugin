import 'dart:async';

import 'package:ai_pos_floating_workspace/ai_pos_floating_workspace.dart';
import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'plugin_page_shell.dart';
import 'plugin_page_shell_strings.dart';
import 'plugin_session_host_controller.dart';
import 'plugin_session_request.dart';

/// Compatibility boundary that maps the plugin runtime onto one workspace
/// domain without exposing workspace internals to third-party integrations.
final class AiPosPluginWorkspaceAdapter
    implements AiPosPluginSessionHostDelegate {
  AiPosPluginWorkspaceAdapter({
    required this.controller,
    required this.domainController,
    AiPosPluginPageShellStrings strings = const AiPosPluginPageShellStrings(
      floatingLabel: 'Float',
    ),
    AiPosPluginActionSheetPresenter? actionSheetPresenter,
  }) : _strings = strings,
       _actionSheetPresenter = actionSheetPresenter {
    final actual = domainController.policy;
    if (actual.domainId != policy.domainId ||
        actual.maxFloatingSessions != policy.maxFloatingSessions ||
        actual.maxSnapshotBytes != policy.maxSnapshotBytes) {
      throw ArgumentError.value(
        domainController.policy,
        'domainController',
        'must use AiPosPluginWorkspaceAdapter.policy',
      );
    }
    controller.attachHost(this);
  }

  static const policy = FloatingDomainPolicy(
    domainId: 'plugin',
    maxFloatingSessions: 5,
    maxSnapshotBytes: 12 * 1024 * 1024,
  );

  final AiPosPluginSessionHostController controller;
  final FloatingDomainController domainController;
  AiPosPluginPageShellStrings _strings;
  AiPosPluginActionSheetPresenter? _actionSheetPresenter;
  final Map<String, _PluginWorkspaceSession> _sessions = {};
  Future<void>? _disposeFuture;
  bool _disposed = false;

  @override
  Future<Object?> open(AiPosPluginSessionRequest request) {
    if (_disposed) {
      throw StateError('The plugin workspace adapter is disposed.');
    }
    final existing = _sessions[request.pluginId];
    if (existing != null) {
      if (existing.visibility.value == AiPosPluginPageVisibility.closing ||
          existing.pendingReopen) {
        if (existing.pendingReopen) existing.dispose();
        return _openNewSession(request, pendingReopen: true);
      }
      return domainController.open(existing.floatingRequest);
    }

    return _openNewSession(request);
  }

  Future<Object?> _openNewSession(
    AiPosPluginSessionRequest request, {
    bool pendingReopen = false,
  }) {
    final session = _PluginWorkspaceSession(
      request,
      pendingReopen: pendingReopen,
    );
    late final FloatingSessionRequest floatingRequest;
    floatingRequest = FloatingSessionRequest(
      key: FloatingSessionKey(
        domainId: policy.domainId,
        sessionId: request.pluginId,
      ),
      title: request.pluginName,
      pageBuilder: (context, actions) {
        final mappedActions = _PluginWorkspaceActions(session, actions);
        return AiPosPluginPageShell(
          pageBuilder: request.pageBuilder,
          pluginName: request.pluginName,
          pluginDescription: request.pluginDescription,
          controller: session.shellController,
          visibilityListenable: session.visibility,
          strings: _strings,
          actionSheetPresenter: _actionSheetPresenter,
          onRequestFloat: mappedActions.float,
          onRequestRestart: mappedActions.restart,
          onRequestClose: mappedActions.close,
          handleSystemBack: false,
        );
      },
      maybePopNested: session.shellController.maybePopNested,
      onVisibilityChanged: (visibility) {
        if (visibility == FloatingSessionVisibility.foreground) {
          session.pendingReopen = false;
        }
        if (!session.visibility.isDisposed) {
          session.visibility.value = _mapVisibility(visibility);
        }
      },
      onClosed: (result) {
        if (session.restarting) {
          return;
        }
        if (identical(_sessions[request.pluginId], session)) {
          _sessions.remove(request.pluginId);
        }
        session.dispose();
      },
    );
    session.floatingRequest = floatingRequest;
    _sessions[request.pluginId] = session;
    try {
      return domainController.open(floatingRequest);
    } catch (_) {
      if (identical(_sessions[request.pluginId], session)) {
        _sessions.remove(request.pluginId);
      }
      session.dispose();
      rethrow;
    }
  }

  static AiPosPluginPageVisibility _mapVisibility(
    FloatingSessionVisibility visibility,
  ) {
    return switch (visibility) {
      FloatingSessionVisibility.foreground =>
        AiPosPluginPageVisibility.foreground,
      FloatingSessionVisibility.floating => AiPosPluginPageVisibility.floating,
      FloatingSessionVisibility.closing => AiPosPluginPageVisibility.closing,
    };
  }

  @override
  Future<void> closeAll() => domainController.closeAll();

  void updatePresentation({
    required AiPosPluginPageShellStrings strings,
    AiPosPluginActionSheetPresenter? actionSheetPresenter,
  }) {
    _strings = strings;
    _actionSheetPresenter = actionSheetPresenter;
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    controller.detachHost(this);
    await domainController.closeAll();
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }
}

final class _PluginWorkspaceSession {
  _PluginWorkspaceSession(this.request, {this.pendingReopen = false});

  final AiPosPluginSessionRequest request;
  final shellController = AiPosPluginPageShellController();
  final visibility = _DisposableValueNotifier<AiPosPluginPageVisibility>(
    AiPosPluginPageVisibility.foreground,
  );
  late final FloatingSessionRequest floatingRequest;
  bool pendingReopen;
  bool restarting = false;

  void dispose() => visibility.dispose();
}

final class _PluginWorkspaceActions {
  const _PluginWorkspaceActions(this.session, this.delegate);

  final _PluginWorkspaceSession session;
  final FloatingSessionActions delegate;

  Future<void> float() => delegate.float();

  Future<void> close(Object? result) => delegate.close(result);

  Future<void> restart() async {
    session.restarting = true;
    try {
      await delegate.restart();
    } finally {
      session.restarting = false;
    }
  }
}

final class _DisposableValueNotifier<T> extends ValueNotifier<T> {
  _DisposableValueNotifier(super.value);

  bool isDisposed = false;

  @override
  void dispose() {
    if (isDisposed) {
      return;
    }
    isDisposed = true;
    super.dispose();
  }
}
