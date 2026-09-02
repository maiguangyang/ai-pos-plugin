import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:flutter/foundation.dart';

@immutable
final class AiPosPluginSessionRequest {
  const AiPosPluginSessionRequest({
    required this.pluginId,
    required this.pluginName,
    this.pluginDescription = '',
    required this.pagePath,
    required this.pageBuilder,
  });

  final String pluginId;
  final String pluginName;
  final String pluginDescription;
  final String pagePath;
  final AiPosPluginPageBuilder pageBuilder;
}
