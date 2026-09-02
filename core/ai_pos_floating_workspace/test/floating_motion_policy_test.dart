import 'package:ai_pos_floating_workspace/ai_pos_floating_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('drag and velocity resolve bounded reveal targets', () {
    final policy = FloatingMotionPolicy();

    expect(policy.progressForDrag(dx: -160, revealExtent: 320), 0.5);
    expect(policy.progressForDrag(dx: 40, revealExtent: 320), 0);
    expect(policy.targetForRelease(progress: 0.49, velocityX: 0), 0);
    expect(policy.targetForRelease(progress: 0.49, velocityX: -1000), 1);
  });

  test('settle duration remains inside configured bounds', () {
    final policy = FloatingMotionPolicy();

    expect(
      policy.settleDuration(progress: 0, target: 1, velocityX: 0),
      const Duration(milliseconds: 320),
    );
    expect(
      policy.settleDuration(progress: 0, target: 1, velocityX: 5000),
      const Duration(milliseconds: 160),
    );
  });

  test('invalid motion configuration and reveal extent are rejected', () {
    expect(() => FloatingMotionPolicy(openThreshold: 2), throwsArgumentError);
    expect(
      () => FloatingMotionPolicy().progressForDrag(dx: 1, revealExtent: 0),
      throwsArgumentError,
    );
  });
}
