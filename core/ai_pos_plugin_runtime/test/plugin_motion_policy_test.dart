import 'package:ai_pos_plugin_runtime/ai_pos_plugin_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final policy = AiPosPluginMotionPolicy();

  test('drag progress is continuous and clamped', () {
    expect(policy.progressForDrag(dx: -160, revealExtent: 320), 0.5);
    expect(policy.progressForDrag(dx: 40, revealExtent: 320), 0);
    expect(policy.progressForDrag(dx: -480, revealExtent: 320), 1);
    expect(
      () => policy.progressForDrag(dx: -1, revealExtent: 0),
      throwsArgumentError,
    );
  });

  test('release target combines position with horizontal velocity', () {
    expect(policy.targetForRelease(progress: 0.2, velocityX: -1800), 1);
    expect(policy.targetForRelease(progress: 0.3, velocityX: 0), 0);
    expect(policy.targetForRelease(progress: 0.8, velocityX: 1800), 0);
  });

  test('settle duration remains inside the motion budget', () {
    expect(
      policy.settleDuration(progress: 0, target: 1, velocityX: 0),
      allOf(
        greaterThanOrEqualTo(const Duration(milliseconds: 160)),
        lessThanOrEqualTo(const Duration(milliseconds: 320)),
      ),
    );
    expect(
      policy.settleDuration(progress: 0.9, target: 1, velocityX: -5000),
      const Duration(milliseconds: 160),
    );
  });
}
