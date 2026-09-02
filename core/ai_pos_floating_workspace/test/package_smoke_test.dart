// The import itself is the smoke assertion: this test must compile through the
// package's public entrypoint before the remaining primitives are introduced.
// ignore_for_file: unused_import

import 'package:ai_pos_floating_workspace/ai_pos_floating_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public package entrypoint compiles', () {
    expect(true, isTrue);
  });
}
