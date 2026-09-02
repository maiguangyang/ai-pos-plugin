import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plugin repository exposes documentation and one verification gate', () {
    final root = findPluginRoot(Directory.current);
    final makefile = File('${root.path}/Makefile');
    final readme = File('${root.path}/README.md');
    final integrations = File('${root.path}/integrations/README.md');
    final ignore = File('${root.path}/.gitignore');
    final iosProject = File(
      '${root.path}/example/plugin_host/ios/Runner.xcodeproj/project.pbxproj',
    );
    final demoMetadata = File(
      '${root.path}/integrations/easypos_demo/integration.yaml',
    );
    final demoPackage = Directory(
      '${root.path}/integrations/easypos_demo/packages/easypos_demo_integration',
    );
    final demoApp = Directory(
      '${root.path}/integrations/easypos_demo/apps/easypos_demo_app',
    );

    expect(makefile.existsSync(), isTrue);
    expect(readme.existsSync(), isTrue);
    expect(integrations.existsSync(), isTrue);
    expect(ignore.existsSync(), isTrue);
    expect(demoMetadata.existsSync(), isTrue);
    expect(demoPackage.existsSync(), isTrue);
    expect(demoApp.existsSync(), isTrue);
    expect(makefile.readAsStringSync(), contains('verify:'));
    expect(makefile.readAsStringSync(), contains('boundaries:'));
    expect(readme.readAsStringSync(), contains('make verify'));
    expect(integrations.readAsStringSync(), contains('package:ai_pos_app'));
    expect(iosProject.readAsStringSync(), isNot(contains('DEVELOPMENT_TEAM')));
  });
}

Directory findPluginRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    final apiPubspec = File(
      '${current.path}/core/ai_pos_plugin_api/pubspec.yaml',
    );
    if (apiPubspec.existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('ai-pos-plugin root not found');
    }
    current = parent;
  }
}
