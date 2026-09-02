import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CLI rejects invalid arguments', () async {
    final result = await Process.run('dart', [
      'run',
      'bin/check_import_boundaries.dart',
    ]);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Usage:'));
  });

  test('CLI prints violations and exits non-zero', () async {
    final root = await Directory.systemTemp.createTemp('ai_pos_plugin_cli_');
    addTearDown(() => root.delete(recursive: true));
    final integration = Directory(
      '${root.path}/integrations/vendor_a/packages/vendor_a/lib',
    );
    await integration.create(recursive: true);
    await File(
      '${root.path}/integrations/vendor_a/packages/vendor_a/pubspec.yaml',
    ).writeAsString('name: vendor_a\n');
    await File(
      '${integration.path}/main.dart',
    ).writeAsString("import 'package:ai_pos_app/main.dart';");

    final result = await Process.run('dart', [
      'run',
      'bin/check_import_boundaries.dart',
      '--root',
      root.path,
    ]);

    expect(result.exitCode, 1);
    expect(
      result.stdout,
      contains(
        'integrations/vendor_a/packages/vendor_a/lib/main.dart: forbidden import '
        'package:ai_pos_app/main.dart',
      ),
    );
  });
}
