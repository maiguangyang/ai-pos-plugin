import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:flutter/widgets.dart';

/// 第三方插件测试可直接使用的最小宿主上下文。
final class FakeAiPosPluginContext implements AiPosPluginContext {
  FakeAiPosPluginContext({
    required this.locale,
    Set<AiPosCapability> grantedCapabilities = const {},
  }) : grantedCapabilities = Set<AiPosCapability>.unmodifiable(
         grantedCapabilities,
       );

  @override
  final Locale locale;

  @override
  final Set<AiPosCapability> grantedCapabilities;
}
