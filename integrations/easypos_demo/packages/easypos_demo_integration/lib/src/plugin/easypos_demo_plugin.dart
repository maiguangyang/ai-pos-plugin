import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import '../orders/demo_order_home_page.dart';
import '../orders/demo_order_runtime.dart';

/// EasyPOS-owned delivery demo used to validate the public plugin contract.
final class EasyPosDemoPlugin implements AiPosPlugin {
  EasyPosDemoPlugin({EasyPosDemoRuntime? runtime})
    : runtime = runtime ?? EasyPosDemoRuntime();

  final EasyPosDemoRuntime runtime;

  @override
  final AiPosPluginManifest manifest = AiPosPluginManifest(
    id: 'com.sjfood.easypos.demo',
    name: 'EasyPOS Demo Delivery',
    description: '独立配送订单演示，由第三方业务包提供页面和业务状态。',
    version: '0.3.0',
    requiredApiVersion: const AiPosPluginApiVersion(major: 0, minor: 3),
    entryPage: '/orders',
    capabilities: const {},
  );

  @override
  late final Map<String, AiPosPluginPageBuilder> pages =
      Map<String, AiPosPluginPageBuilder>.unmodifiable({
        '/orders': (_, pageContext) => EasyPosDemoOrdersPage(
          runtime: runtime,
          visibilityListenable: pageContext.visibilityListenable,
          onComplete: (result) => pageContext.close(result: result),
        ),
      });

  @override
  Future<void> initialize(
    AiPosPluginContext context,
    AiPosPluginLifecycle lifecycle,
  ) async {
    try {
      lifecycle.throwIfCancellationRequested();
      await runtime.start();
      lifecycle.throwIfCancellationRequested();
    } catch (_) {
      await runtime.dispose();
      rethrow;
    }
  }

  @override
  Future<void> dispose() => runtime.dispose();
}
