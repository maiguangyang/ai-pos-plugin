import 'dart:async';

import 'package:flutter/material.dart';

import 'floating_page_capsule.dart';

@immutable
final class FloatingPageAction {
  const FloatingPageAction({required this.id, required this.label});

  final String id;
  final String label;
}

abstract interface class _FloatingPageShellDelegate {
  Future<bool> maybePopNested();
}

final class FloatingPageShellController {
  _FloatingPageShellDelegate? _delegate;

  Future<bool> maybePopNested() async {
    return await _delegate?.maybePopNested() ?? false;
  }

  void _attach(_FloatingPageShellDelegate delegate) {
    final current = _delegate;
    if (current != null && !identical(current, delegate)) {
      throw StateError(
        'The floating page shell controller is already attached.',
      );
    }
    _delegate = delegate;
  }

  void _detach(_FloatingPageShellDelegate delegate) {
    if (identical(_delegate, delegate)) {
      _delegate = null;
    }
  }
}

final class FloatingPageShell extends StatefulWidget {
  const FloatingPageShell({
    super.key,
    required this.title,
    required this.pageBuilder,
    required this.actions,
    required this.presentActions,
    required this.onAction,
    required this.onClose,
    required this.controller,
    this.handleSystemBack = true,
  });

  static const capsuleKey = Key('ai-pos-floating-page-capsule');
  static const capsuleSurfaceKey = Key('ai-pos-floating-page-capsule-surface');
  static const moreButtonKey = Key('ai-pos-floating-page-more');
  static const closeButtonKey = Key('ai-pos-floating-page-close');

  final String title;
  final WidgetBuilder pageBuilder;
  final List<FloatingPageAction> actions;
  final Future<String?> Function(
    BuildContext context,
    List<FloatingPageAction> actions,
  )
  presentActions;

  /// Runs the selected action with the nested Navigator's overlay context.
  ///
  /// The shell can be hosted outside the application's route Navigator, so
  /// callers that present follow-up UI must not fall back to their build
  /// context.
  final FutureOr<void> Function(BuildContext context, String id) onAction;
  final VoidCallback onClose;
  final FloatingPageShellController controller;
  final bool handleSystemBack;

  @override
  State<FloatingPageShell> createState() => _FloatingPageShellState();
}

final class _FloatingPageShellState extends State<FloatingPageShell>
    implements _FloatingPageShellDelegate {
  final _nestedNavigatorKey = GlobalKey<NavigatorState>();
  late final HeroController _heroController;
  bool _presentingActions = false;

  @override
  void initState() {
    super.initState();
    _heroController = MaterialApp.createMaterialHeroController();
    widget.controller._attach(this);
  }

  @override
  void didUpdateWidget(covariant FloatingPageShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._detach(this);
      widget.controller._attach(this);
    }
  }

  @override
  Future<bool> maybePopNested() async {
    return await _nestedNavigatorKey.currentState?.maybePop() ?? false;
  }

  Future<void> _showActions() async {
    if (_presentingActions) {
      return;
    }
    final actionContext = _nestedNavigatorKey.currentState?.overlay?.context;
    if (actionContext == null) {
      return;
    }
    setState(() => _presentingActions = true);
    String? selected;
    try {
      selected = await widget.presentActions(actionContext, widget.actions);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'while presenting floating page actions');
    } finally {
      if (mounted) {
        setState(() => _presentingActions = false);
      }
    }
    if (!mounted || !actionContext.mounted || selected == null) {
      return;
    }
    try {
      await widget.onAction(actionContext, selected);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'while running a floating page action');
    }
  }

  void _report(Object error, StackTrace stackTrace, String description) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'ai_pos_floating_workspace',
        context: ErrorDescription(description),
      ),
    );
  }

  Future<void> _handleSystemBack() async {
    if (!await maybePopNested() && mounted) {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nestedNavigator = HeroControllerScope(
      controller: _heroController,
      child: Navigator(
        key: _nestedNavigatorKey,
        onGenerateInitialRoutes: (_, _) => [
          MaterialPageRoute<Object?>(builder: widget.pageBuilder),
        ],
      ),
    );
    return PopScope<Object?>(
      canPop: !widget.handleSystemBack,
      onPopInvokedWithResult: (didPop, _) {
        if (widget.handleSystemBack && !didPop) {
          unawaited(_handleSystemBack());
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          nestedNavigator,
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, right: 12),
              child: Align(
                alignment: Alignment.topRight,
                child: FloatingPageCapsule(
                  key: FloatingPageShell.capsuleKey,
                  surfaceKey: FloatingPageShell.capsuleSurfaceKey,
                  moreButtonKey: FloatingPageShell.moreButtonKey,
                  closeButtonKey: FloatingPageShell.closeButtonKey,
                  menuOpen: _presentingActions,
                  onMore: () => unawaited(_showActions()),
                  onClose: widget.onClose,
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
    widget.controller._detach(this);
    _heroController.dispose();
    super.dispose();
  }
}
