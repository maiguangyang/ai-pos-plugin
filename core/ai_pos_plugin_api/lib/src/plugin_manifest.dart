import 'package:flutter/foundation.dart';

import 'plugin_api_version.dart';
import 'plugin_capability.dart';

/// 插件在编译期向宿主声明的身份、入口与能力需求。
@immutable
final class AiPosPluginManifest {
  AiPosPluginManifest({
    required this.id,
    required this.name,
    this.description = '',
    required this.version,
    required this.requiredApiVersion,
    required this.entryPage,
    required Set<AiPosCapability> capabilities,
  }) : capabilities = Set<AiPosCapability>.unmodifiable(capabilities);

  final String id;
  final String name;
  final String description;
  final String version;
  final AiPosPluginApiVersion requiredApiVersion;
  final String entryPage;
  final Set<AiPosCapability> capabilities;
}
