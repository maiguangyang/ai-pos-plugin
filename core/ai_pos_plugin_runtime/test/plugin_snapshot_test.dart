import 'package:ai_pos_plugin_runtime/ai_pos_plugin_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('snapshot reports byte cost and disposes its resource once', (
    tester,
  ) async {
    var disposeCount = 0;
    final snapshot = AiPosPluginSnapshot(
      width: 480,
      height: 800,
      builder: ({key, required fit}) =>
          ColoredBox(key: key, color: Colors.blue),
      onDispose: () => disposeCount += 1,
    );

    expect(snapshot.estimatedBytes, 480 * 800 * 4);
    await tester.pumpWidget(snapshot.build(key: const Key('snapshot')));
    expect(find.byKey(const Key('snapshot')), findsOneWidget);

    snapshot.dispose();
    snapshot.dispose();

    expect(snapshot.isDisposed, isTrue);
    expect(disposeCount, 1);
    expect(() => snapshot.build(), throwsStateError);
  });

  test('snapshot rejects invalid physical dimensions', () {
    expect(
      () => AiPosPluginSnapshot(
        width: 0,
        height: 10,
        builder: ({key, required fit}) => const SizedBox.shrink(),
        onDispose: () {},
      ),
      throwsArgumentError,
    );
  });
}
