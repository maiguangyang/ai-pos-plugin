import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:flutter/material.dart';

/// 可复制为第三方业务包起点的最小示例插件。
final class AiPosExamplePlugin implements AiPosPlugin {
  @override
  final AiPosPluginManifest manifest = AiPosPluginManifest(
    id: 'com.sjfood.example',
    name: 'AI POS Example',
    description: 'A standalone third-party integration example.',
    version: '0.3.0',
    requiredApiVersion: const AiPosPluginApiVersion(major: 0, minor: 3),
    entryPage: '/home',
    capabilities: const {},
  );

  @override
  late final Map<String, AiPosPluginPageBuilder> pages =
      Map<String, AiPosPluginPageBuilder>.unmodifiable({
        '/home': (_, _) => const AiPosExampleHomePage(),
      });

  @override
  Future<void> initialize(
    AiPosPluginContext context,
    AiPosPluginLifecycle lifecycle,
  ) async {
    lifecycle.throwIfCancellationRequested();
  }

  @override
  Future<void> dispose() async {}
}

/// 示例插件的入口页面。
class AiPosExampleHomePage extends StatelessWidget {
  const AiPosExampleHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        key: Key('ai-pos-example-plugin-ready'),
        child: Text('Example integration ready'),
      ),
    );
  }
}
