import 'package:flutter/foundation.dart';

/// 宿主运行时可稳定识别的插件错误分类。
enum AiPosPluginErrorCode {
  invalidManifest,
  duplicatePluginId,
  incompatibleApiVersion,
  capabilityDenied,
  pluginNotFound,
  pageNotFound,
  initializationFailed,
  initializationTimedOut,
  initializationCancelled,
  disposalFailed,
  disposalTimedOut,
  registryClosed,
}

/// 不在显示字符串中暴露第三方原始异常的运行时错误。
@immutable
final class AiPosPluginException implements Exception {
  const AiPosPluginException({
    required this.code,
    required this.pluginId,
    required this.pluginVersion,
    this.relatedCode,
  });

  final AiPosPluginErrorCode code;
  final String pluginId;
  final String pluginVersion;

  /// 同一生命周期操作中发生的次要稳定错误分类。
  final AiPosPluginErrorCode? relatedCode;

  @override
  String toString() {
    return 'AiPosPluginException('
        'code: ${code.name}, '
        'pluginId: $pluginId, '
        'pluginVersion: $pluginVersion, '
        'relatedCode: ${relatedCode?.name})';
  }
}
