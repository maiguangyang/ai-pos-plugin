import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'make verification discovers every integration package and app',
    () async {
      final fixture = await Directory.systemTemp.createTemp(
        'ai_pos_plugin_make_discovery_',
      );
      addTearDown(() => fixture.delete(recursive: true));
      for (final path in [
        'integrations/vendor_a/packages/vendor_a_integration/pubspec.yaml',
        'integrations/vendor_a/apps/vendor_a_app/pubspec.yaml',
        'integrations/vendor_b/packages/vendor_b_integration/pubspec.yaml',
        'integrations/vendor_b/apps/vendor_b_app/pubspec.yaml',
      ]) {
        final pubspec = File('${fixture.path}/$path');
        await pubspec.parent.create(recursive: true);
        await pubspec.writeAsString('name: fixture\n');
      }
      final makefile = File('../../Makefile').absolute.path;

      final result = await Process.run('make', [
        '--no-print-directory',
        '-s',
        '-f',
        makefile,
        'list_package_dirs',
        'PLUGIN_ROOT=${fixture.path}',
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final discovered = (result.stdout as String)
          .split('\n')
          .where((line) => line.isNotEmpty)
          .toSet();
      expect(
        discovered,
        containsAll(<String>{
          '${fixture.path}/integrations/vendor_a/packages/vendor_a_integration',
          '${fixture.path}/integrations/vendor_a/apps/vendor_a_app',
          '${fixture.path}/integrations/vendor_b/packages/vendor_b_integration',
          '${fixture.path}/integrations/vendor_b/apps/vendor_b_app',
        }),
      );
    },
  );
}
