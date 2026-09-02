import 'package:flutter/foundation.dart';

@immutable
final class AiPosPluginPageShellStrings {
  const AiPosPluginPageShellStrings({
    required this.floatingLabel,
    this.restartLabel = 'Restart mini app',
    this.descriptionFallback = 'Third-party application',
    this.floatingDockLabel = 'Open floating windows',
    this.floatingCardOpenLabel = 'Open',
    this.floatingCardCloseLabel = 'Close',
  });

  final String floatingLabel;
  final String restartLabel;
  final String descriptionFallback;
  final String floatingDockLabel;
  final String floatingCardOpenLabel;
  final String floatingCardCloseLabel;
}
