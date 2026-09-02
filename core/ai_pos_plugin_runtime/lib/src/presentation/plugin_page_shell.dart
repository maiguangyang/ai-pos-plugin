import 'dart:async';

import 'package:ai_pos_floating_workspace/ai_pos_floating_workspace.dart';
import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'plugin_page_shell_strings.dart';

typedef AiPosPluginPageCloseCallback = void Function(Object? result);
typedef AiPosPluginPageFloatCallback = FutureOr<void> Function();
typedef AiPosPluginPageRestartCallback = FutureOr<void> Function();
typedef AiPosPluginActionSheetPresenter =
    Future<AiPosPluginActionSheetAction?> Function(
      BuildContext context,
      AiPosPluginActionSheetRequest request,
    );

enum AiPosPluginActionSheetAction { float, restart }

@immutable
final class AiPosPluginActionSheetRequest {
  const AiPosPluginActionSheetRequest({
    required this.pluginName,
    required this.pluginDescription,
    required this.strings,
    required this.floatEnabled,
  });

  final String pluginName;
  final String pluginDescription;
  final AiPosPluginPageShellStrings strings;
  final bool floatEnabled;
}

/// A host-owned handle for the nested Navigator inside a page shell.
final class AiPosPluginPageShellController {
  _AiPosPluginPageShellDelegate? _delegate;

  Future<bool> maybePopNested() async {
    return await _delegate?.maybePopNested() ?? false;
  }

  void _attach(_AiPosPluginPageShellDelegate delegate) {
    final current = _delegate;
    if (current != null && !identical(current, delegate)) {
      throw StateError('The shell controller is already attached.');
    }
    _delegate = delegate;
  }

  void _detach(_AiPosPluginPageShellDelegate delegate) {
    if (identical(_delegate, delegate)) {
      _delegate = null;
    }
  }
}

abstract interface class _AiPosPluginPageShellDelegate {
  Future<bool> maybePopNested();
}

/// Host-owned fullscreen boundary for one plugin page stack.
final class AiPosPluginPageShell extends StatefulWidget {
  const AiPosPluginPageShell({
    super.key,
    required this.pageBuilder,
    this.pluginName = 'Mini app',
    this.pluginDescription = '',
    this.controller,
    this.visibilityListenable,
    this.strings = const AiPosPluginPageShellStrings(floatingLabel: 'Float'),
    this.actionSheetPresenter,
    this.onRequestFloat,
    this.onRequestRestart,
    this.onRequestClose,
    this.handleSystemBack = true,
  });

  static const capsuleKey = Key('ai-pos-plugin-host-capsule');
  static const capsuleSurfaceKey = Key('ai-pos-plugin-host-capsule-surface');
  static const moreButtonKey = Key('ai-pos-plugin-host-more');
  static const closeButtonKey = Key('ai-pos-plugin-host-close');
  static const actionSheetKey = Key('ai-pos-plugin-host-action-sheet');
  static const appIntroductionKey = Key('ai-pos-plugin-host-app-introduction');
  static const floatActionKey = Key('ai-pos-plugin-host-float-action');
  static const restartActionKey = Key('ai-pos-plugin-host-restart-action');

  final AiPosPluginPageBuilder pageBuilder;
  final String pluginName;
  final String pluginDescription;
  final AiPosPluginPageShellController? controller;
  final ValueListenable<AiPosPluginPageVisibility>? visibilityListenable;
  final AiPosPluginPageShellStrings strings;
  final AiPosPluginActionSheetPresenter? actionSheetPresenter;
  final AiPosPluginPageFloatCallback? onRequestFloat;
  final AiPosPluginPageRestartCallback? onRequestRestart;
  final AiPosPluginPageCloseCallback? onRequestClose;
  final bool handleSystemBack;

  @override
  State<AiPosPluginPageShell> createState() => _AiPosPluginPageShellState();
}

final class _AiPosPluginPageShellState extends State<AiPosPluginPageShell>
    implements _AiPosPluginPageShellDelegate {
  final _nestedNavigatorKey = GlobalKey<NavigatorState>();
  final _restartGeneration = ValueNotifier<int>(0);
  late final HeroController _heroController;
  late final _RoutePageContext _pageContext;
  ValueNotifier<AiPosPluginPageVisibility>? _ownedVisibility;
  late ValueListenable<AiPosPluginPageVisibility> _visibility;
  NavigatorState? _outerNavigator;
  Route<Object?>? _outerRoute;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    _heroController = MaterialApp.createMaterialHeroController();
    _visibility = _resolveVisibility(widget.visibilityListenable);
    _pageContext = _RoutePageContext(_visibility)..attach(_requestClose);
    widget.controller?._attach(this);
  }

  ValueListenable<AiPosPluginPageVisibility> _resolveVisibility(
    ValueListenable<AiPosPluginPageVisibility>? external,
  ) {
    if (external != null) {
      return external;
    }
    return _ownedVisibility = ValueNotifier<AiPosPluginPageVisibility>(
      AiPosPluginPageVisibility.foreground,
    );
  }

  @override
  void didUpdateWidget(covariant AiPosPluginPageShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (!identical(
      oldWidget.visibilityListenable,
      widget.visibilityListenable,
    )) {
      _ownedVisibility?.dispose();
      _ownedVisibility = null;
      _visibility = _resolveVisibility(widget.visibilityListenable);
      _pageContext.updateVisibility(_visibility);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _outerNavigator = Navigator.maybeOf(context);
    _outerRoute = ModalRoute.of<Object?>(context);
  }

  void _requestClose(Object? result) {
    final externalClose = widget.onRequestClose;
    if (externalClose != null) {
      externalClose(result);
      return;
    }
    final navigator = _outerNavigator;
    final route = _outerRoute;
    if (!mounted || navigator == null || route == null || !route.isActive) {
      return;
    }
    navigator.removeRoute<Object?>(route, result);
  }

  Future<void> _showActionSheet() async {
    final navigator = _nestedNavigatorKey.currentState;
    final sheetContext = navigator?.overlay?.context;
    if (navigator == null || sheetContext == null) {
      return;
    }
    if (_sheetOpen) {
      navigator.maybePop();
      return;
    }
    setState(() => _sheetOpen = true);
    final request = AiPosPluginActionSheetRequest(
      pluginName: widget.pluginName,
      pluginDescription: widget.pluginDescription.isEmpty
          ? widget.strings.descriptionFallback
          : widget.pluginDescription,
      strings: widget.strings,
      floatEnabled: widget.onRequestFloat != null,
    );
    final presenter = widget.actionSheetPresenter;
    AiPosPluginActionSheetAction? action;
    try {
      action = presenter == null
          ? await _showDefaultActionSheet(
              navigator: navigator,
              context: sheetContext,
              request: request,
            )
          : await presenter(sheetContext, request);
    } finally {
      if (mounted) {
        setState(() => _sheetOpen = false);
      }
    }
    if (!mounted) {
      return;
    }
    switch (action) {
      case AiPosPluginActionSheetAction.float:
        _requestFloat();
      case AiPosPluginActionSheetAction.restart:
        _requestRestart();
      case null:
        break;
    }
  }

  Future<void> _runHostOperation(
    FutureOr<void> Function() operation,
    String description,
  ) async {
    try {
      await operation();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'ai_pos_plugin_runtime',
          context: ErrorDescription(description),
        ),
      );
    }
  }

  Future<AiPosPluginActionSheetAction?> _showDefaultActionSheet({
    required NavigatorState navigator,
    required BuildContext context,
    required AiPosPluginActionSheetRequest request,
  }) async {
    final localizations = MaterialLocalizations.of(context);
    final route = ModalBottomSheetRoute<AiPosPluginActionSheetAction>(
      builder: (context) => AiPosPluginActionSheetContent(
        request: request,
        onSelected: (action) => Navigator.of(context).pop(action),
      ),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: false,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      modalBarrierColor: Colors.black.withValues(alpha: 0.48),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
    final action = await navigator.push(route);
    await route.completed;
    return action;
  }

  void _requestFloat() {
    final callback = widget.onRequestFloat;
    if (callback == null) {
      return;
    }
    unawaited(
      _runHostOperation(callback, 'while requesting a floating plugin session'),
    );
  }

  void _requestRestart() {
    final callback = widget.onRequestRestart;
    if (callback == null) {
      _restartMiniApp();
      return;
    }
    unawaited(
      _runHostOperation(callback, 'while restarting the plugin session'),
    );
  }

  void _restartMiniApp() {
    final navigator = _nestedNavigatorKey.currentState;
    if (navigator == null) {
      return;
    }
    navigator.popUntil((route) => route.isFirst);
    _restartGeneration.value += 1;
  }

  @override
  Future<bool> maybePopNested() async {
    return await _nestedNavigatorKey.currentState?.maybePop() ?? false;
  }

  void _handleBack(bool didPop) {
    if (didPop) {
      return;
    }
    if (widget.onRequestClose != null) {
      unawaited(_popNestedOrCloseSession());
    }
  }

  Future<void> _popNestedOrCloseSession() async {
    final popped = await maybePopNested();
    if (!popped && mounted) {
      _requestClose(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nestedNavigator = HeroControllerScope(
      controller: _heroController,
      child: Navigator(
        key: _nestedNavigatorKey,
        onGenerateInitialRoutes: (_, _) => [
          MaterialPageRoute<Object?>(
            builder: (_) => ValueListenableBuilder<int>(
              valueListenable: _restartGeneration,
              builder: (_, generation, _) => _PluginPageBoundary(
                key: ValueKey<int>(generation),
                pageBuilder: widget.pageBuilder,
                pageContext: _pageContext,
              ),
            ),
          ),
        ],
      ),
    );
    final hasSessionClose = widget.onRequestClose != null;
    final handlesSystemBack = hasSessionClose && widget.handleSystemBack;
    return PopScope<Object?>(
      canPop: !handlesSystemBack,
      onPopInvokedWithResult: (didPop, _) {
        if (handlesSystemBack) {
          _handleBack(didPop);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasSessionClose)
            nestedNavigator
          else
            NavigatorPopHandler<Object?>(
              onPopWithResult: (result) {
                unawaited(_nestedNavigatorKey.currentState?.maybePop(result));
              },
              child: nestedNavigator,
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, right: 12),
              child: Align(
                alignment: Alignment.topRight,
                child: FloatingPageCapsule(
                  key: AiPosPluginPageShell.capsuleKey,
                  surfaceKey: AiPosPluginPageShell.capsuleSurfaceKey,
                  moreButtonKey: AiPosPluginPageShell.moreButtonKey,
                  closeButtonKey: AiPosPluginPageShell.closeButtonKey,
                  menuOpen: _sheetOpen,
                  onMore: () => unawaited(
                    _runHostOperation(
                      _showActionSheet,
                      'while presenting the plugin action sheet',
                    ),
                  ),
                  onClose: _pageContext.close,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _pageContext.invalidate();
    _ownedVisibility?.dispose();
    _restartGeneration.dispose();
    _heroController.dispose();
    _outerNavigator = null;
    _outerRoute = null;
    super.dispose();
  }
}

final class _PluginPageBoundary extends StatelessWidget {
  const _PluginPageBoundary({
    super.key,
    required this.pageBuilder,
    required this.pageContext,
  });

  final AiPosPluginPageBuilder pageBuilder;
  final AiPosPluginPageContext pageContext;

  @override
  Widget build(BuildContext context) => pageBuilder(context, pageContext);
}

final class AiPosPluginActionSheetContent extends StatelessWidget {
  const AiPosPluginActionSheetContent({
    super.key,
    required this.request,
    required this.onSelected,
  });

  final AiPosPluginActionSheetRequest request;
  final ValueChanged<AiPosPluginActionSheetAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FloatingActionSheetContent<AiPosPluginActionSheetAction>(
      surfaceKey: AiPosPluginPageShell.actionSheetKey,
      introductionKey: AiPosPluginPageShell.appIntroductionKey,
      leading: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.apps_rounded, size: 24, color: colors.onSurface),
      ),
      title: request.pluginName,
      description: request.pluginDescription,
      items: [
        FloatingActionSheetItem(
          value: AiPosPluginActionSheetAction.float,
          surfaceKey: AiPosPluginPageShell.floatActionKey,
          icon: Icons.picture_in_picture_alt_rounded,
          label: request.strings.floatingLabel,
          enabled: request.floatEnabled,
        ),
        FloatingActionSheetItem(
          value: AiPosPluginActionSheetAction.restart,
          surfaceKey: AiPosPluginPageShell.restartActionKey,
          icon: Icons.refresh_rounded,
          label: request.strings.restartLabel,
        ),
      ],
      onSelected: onSelected,
    );
  }
}

final class _RoutePageContext implements AiPosPluginPageContext {
  _RoutePageContext(this._visibility);

  ValueListenable<AiPosPluginPageVisibility> _visibility;
  void Function(Object? result)? _onClose;

  @override
  AiPosPluginPageVisibility get visibility => _visibility.value;

  @override
  ValueListenable<AiPosPluginPageVisibility> get visibilityListenable =>
      _visibility;

  void attach(void Function(Object? result) onClose) {
    _onClose ??= onClose;
  }

  void updateVisibility(ValueListenable<AiPosPluginPageVisibility> visibility) {
    _visibility = visibility;
  }

  @override
  void close({Object? result}) {
    final onClose = _onClose;
    if (onClose == null) {
      return;
    }
    _onClose = null;
    onClose(result);
  }

  void invalidate() {
    _onClose = null;
  }
}
