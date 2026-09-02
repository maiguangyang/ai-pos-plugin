import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:easypos_demo_integration/easypos_demo_integration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo plugin exposes a valid API 0.3 orders contract', () {
    final plugin = EasyPosDemoPlugin();

    expect(plugin.manifest.id, 'com.sjfood.easypos.demo');
    expect(plugin.manifest.entryPage, '/orders');
    expect(
      plugin.manifest.requiredApiVersion,
      const AiPosPluginApiVersion(major: 0, minor: 3),
    );
    expect(AiPosPluginContractValidator.validate(plugin), isEmpty);
  });
}
