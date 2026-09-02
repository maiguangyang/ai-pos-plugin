import 'package:ai_pos_floating_workspace/ai_pos_floating_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot accounts bytes and disposes exactly once', () {
    var disposeCount = 0;
    final snapshot = FloatingSnapshot.memory(
      width: 20,
      height: 30,
      builder: ({key, required fit}) => SizedBox(key: key),
      onDispose: () => disposeCount += 1,
    );

    expect(snapshot.estimatedBytes, 20 * 30 * 4);
    expect(snapshot.isDisposed, isFalse);
    expect(snapshot.build(key: const Key('snapshot')), isA<SizedBox>());

    snapshot.dispose();
    snapshot.dispose();

    expect(snapshot.isDisposed, isTrue);
    expect(disposeCount, 1);
    expect(snapshot.build, throwsStateError);
  });

  test('snapshot rejects non-positive dimensions', () {
    expect(
      () => FloatingSnapshot.memory(
        width: 0,
        height: 1,
        builder: ({key, required fit}) => const SizedBox(),
        onDispose: () {},
      ),
      throwsArgumentError,
    );
  });
}
