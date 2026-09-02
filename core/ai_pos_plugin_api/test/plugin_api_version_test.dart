import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('0.x compatibility requires the exact major and minor', () {
    const host = AiPosPluginApiVersion(major: 0, minor: 1);

    expect(
      host.supports(const AiPosPluginApiVersion(major: 0, minor: 1)),
      isTrue,
    );
    expect(
      host.supports(const AiPosPluginApiVersion(major: 0, minor: 3)),
      isFalse,
    );
  });

  test('stable compatibility accepts an older required minor', () {
    const host = AiPosPluginApiVersion(major: 1, minor: 4);

    expect(
      host.supports(const AiPosPluginApiVersion(major: 1, minor: 3)),
      isTrue,
    );
    expect(
      host.supports(const AiPosPluginApiVersion(major: 1, minor: 5)),
      isFalse,
    );
    expect(
      host.supports(const AiPosPluginApiVersion(major: 2, minor: 0)),
      isFalse,
    );
  });
}
