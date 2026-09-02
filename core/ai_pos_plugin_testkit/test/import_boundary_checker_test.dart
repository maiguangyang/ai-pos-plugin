import 'dart:io';

import 'package:ai_pos_plugin_testkit/ai_pos_plugin_testkit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows integrations to import the public plugin API', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource: "import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';",
    );

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, isEmpty);
  });

  test('rejects package imports from ai_pos_app', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource: "import 'package:ai_pos_app/shared/index.dart';",
    );

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, hasLength(1));
    expect(
      violations.single.importTarget,
      'package:ai_pos_app/shared/index.dart',
    );
  });

  test('rejects third-party imports from the host runtime', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource:
          "import 'package:ai_pos_plugin_runtime/ai_pos_plugin_runtime.dart';",
    );

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, hasLength(1));
    expect(
      violations.single.importTarget,
      'package:ai_pos_plugin_runtime/ai_pos_plugin_runtime.dart',
    );
  });

  test('rejects third-party imports from the floating workspace', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource:
          "import 'package:ai_pos_floating_workspace/ai_pos_floating_workspace.dart';",
    );

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, hasLength(1));
    expect(
      violations.single.importTarget,
      'package:ai_pos_floating_workspace/ai_pos_floating_workspace.dart',
    );
  });

  test('rejects testkit imports from integration production code', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource:
          "import 'package:ai_pos_plugin_testkit/ai_pos_plugin_testkit.dart';",
    );

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, hasLength(1));
    expect(
      violations.single.importTarget,
      'package:ai_pos_plugin_testkit/ai_pos_plugin_testkit.dart',
    );
  });

  test('allows testkit imports from integration tests', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource: "import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';",
    );
    final testDirectory = Directory(
      '${root.path}/integrations/vendor_a/packages/vendor_a/test',
    );
    await testDirectory.create();
    await File('${testDirectory.path}/plugin_test.dart').writeAsString(
      "import 'package:ai_pos_plugin_testkit/ai_pos_plugin_testkit.dart';",
    );

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, isEmpty);
  });

  test('rejects a host runtime dependency declared in pubspec', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource: "import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';",
    );
    final pubspec = File(
      '${root.path}/integrations/vendor_a/packages/vendor_a/pubspec.yaml',
    );
    await pubspec.writeAsString('''
name: vendor_a
dependencies:
  ai_pos_plugin_runtime:
    path: ../../../../../core/ai_pos_plugin_runtime
''');

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, hasLength(1));
    expect(violations.single.filePath, endsWith('pubspec.yaml'));
    expect(violations.single.importTarget, 'package:ai_pos_plugin_runtime');
  });

  test('rejects testkit as a production dependency', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource: "import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';",
    );
    final pubspec = File(
      '${root.path}/integrations/vendor_a/packages/vendor_a/pubspec.yaml',
    );
    await pubspec.writeAsString('''
name: vendor_a
dependencies:
  ai_pos_plugin_testkit:
    path: ../../../../../core/ai_pos_plugin_testkit
''');

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, hasLength(1));
    expect(violations.single.importTarget, 'package:ai_pos_plugin_testkit');
  });

  test('allows testkit as a development dependency', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource: "import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';",
    );
    final pubspec = File(
      '${root.path}/integrations/vendor_a/packages/vendor_a/pubspec.yaml',
    );
    await pubspec.writeAsString('''
name: vendor_a
dev_dependencies:
  ai_pos_plugin_testkit:
    path: ../../../../../core/ai_pos_plugin_testkit
''');

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, isEmpty);
  });

  test('rejects a testkit path hidden in dependency overrides', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource: "import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';",
    );
    final pubspec = File(
      '${root.path}/integrations/vendor_a/packages/vendor_a/pubspec.yaml',
    );
    await pubspec.writeAsString('''
name: vendor_a
dependency_overrides:
  disguised_test_helper:
    path: ../../../../../core/ai_pos_plugin_testkit
''');

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, hasLength(1));
    expect(violations.single.importTarget, 'package:disguised_test_helper');
  });

  test('rejects relative imports into the host runtime', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource:
          "export '../../../../../core/ai_pos_plugin_runtime/lib/ai_pos_plugin_runtime.dart';",
    );

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, hasLength(1));
  });

  test('rejects forbidden imports when a comment contains a semicolon', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource:
          "import /* a comment containing ; */ 'package:ai_pos_app/main.dart';",
    );

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, hasLength(1));
    expect(violations.single.importTarget, 'package:ai_pos_app/main.dart');
  });

  test('ignores directive-like text inside comments and strings', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource: r'''const documentation = """
import 'package:ai_pos_app/from_string.dart';
""";
// export 'package:ai_pos_app/from_line_comment.dart';
/*
import 'package:ai_pos_app/from_block_comment.dart';
*/
''',
    );

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, isEmpty);
  });

  test(
    'does not treat a standalone workspace app as integration code',
    () async {
      final root = await _fixtureRoot();
      addTearDown(() => root.delete(recursive: true));
      final lib = Directory(
        '${root.path}/integrations/vendor_a/apps/vendor_a_app/lib',
      );
      await lib.create(recursive: true);
      await File(
        '${lib.path}/main.dart',
      ).writeAsString("import 'package:ai_pos_app/main.dart';");

      final violations = const AiPosImportBoundaryChecker().check(root);

      expect(violations, isEmpty);
    },
  );

  test('rejects forbidden conditional import targets', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource: '''
import 'safe.dart'
    if (dart.library.io) 'package:ai_pos_app/main.dart';
''',
    );

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, hasLength(1));
    expect(violations.single.importTarget, 'package:ai_pos_app/main.dart');
  });

  test('rejects forbidden part directive targets', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource:
          "part 'package:ai_pos_plugin_runtime/src/plugin_registry.dart';",
    );

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, hasLength(1));
    expect(
      violations.single.importTarget,
      'package:ai_pos_plugin_runtime/src/plugin_registry.dart',
    );
  });

  test(
    'rejects relative imports containing an ai-pos-app path segment',
    () async {
      final root = await _fixtureRoot();
      addTearDown(() => root.delete(recursive: true));
      await _writeIntegration(
        root,
        directoryName: 'vendor_a',
        packageName: 'vendor_a',
        dartSource:
            "export '../../../../../../../ai-pos-app/lib/shared/index.dart';",
      );

      final violations = const AiPosImportBoundaryChecker().check(root);

      expect(violations, hasLength(1));
      expect(
        violations.single.importTarget,
        '../../../../../../../ai-pos-app/lib/shared/index.dart',
      );
    },
  );

  test('rejects imports from a sibling integration package', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource: "import 'package:vendor_b/vendor_b.dart';",
    );
    await _writeIntegration(
      root,
      directoryName: 'vendor_b',
      packageName: 'vendor_b',
      dartSource: "import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';",
    );

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, hasLength(1));
    expect(violations.single.importTarget, 'package:vendor_b/vendor_b.dart');
  });

  test('rejects relative imports into a sibling integration', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource:
          "import '../../../../vendor_b/packages/vendor_b/lib/main.dart';",
    );
    await _writeIntegration(
      root,
      directoryName: 'vendor_b',
      packageName: 'vendor_b',
      dartSource: "import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';",
    );

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(violations, hasLength(1));
    expect(violations.single.filePath, contains('vendor_a'));
    expect(
      violations.single.importTarget,
      '../../../../vendor_b/packages/vendor_b/lib/main.dart',
    );
  });

  test('sorts multiple violations by file path and then import target', () async {
    final root = await _fixtureRoot();
    addTearDown(() => root.delete(recursive: true));
    await _writeIntegration(
      root,
      directoryName: 'vendor_a',
      packageName: 'vendor_a',
      dartSource: '''
import 'package:ai_pos_app/z.dart';
export 'package:ai_pos_app/a.dart';
''',
    );
    await _writeIntegration(
      root,
      directoryName: 'vendor_b',
      packageName: 'vendor_b',
      dartSource: "import 'package:ai_pos_app/m.dart';",
    );

    final violations = const AiPosImportBoundaryChecker().check(root);

    expect(
      violations.map(
        (violation) => '${violation.filePath}:${violation.importTarget}',
      ),
      [
        'integrations/vendor_a/packages/vendor_a/lib/main.dart:package:ai_pos_app/a.dart',
        'integrations/vendor_a/packages/vendor_a/lib/main.dart:package:ai_pos_app/z.dart',
        'integrations/vendor_b/packages/vendor_b/lib/main.dart:package:ai_pos_app/m.dart',
      ],
    );
  });

  test(
    'scans example packages without treating them as integrations',
    () async {
      final root = await _fixtureRoot();
      addTearDown(() => root.delete(recursive: true));
      await _writeIntegration(
        root,
        directoryName: 'vendor_a',
        packageName: 'vendor_a',
        dartSource:
            "import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';",
      );
      final example = Directory(
        '${root.path}/example/plugin_host/packages/ai_pos_example_plugin/lib',
      );
      await example.create(recursive: true);
      await File(
        '${example.path}/example.dart',
      ).writeAsString("import 'package:ai_pos_app/main.dart';");

      final violations = const AiPosImportBoundaryChecker().check(root);

      expect(violations, hasLength(1));
      expect(violations.single.filePath, contains('ai_pos_example_plugin'));
      expect(violations.single.importTarget, 'package:ai_pos_app/main.dart');
    },
  );
}

Future<Directory> _fixtureRoot() {
  return Directory.systemTemp.createTemp('ai_pos_plugin_boundary_');
}

Future<void> _writeIntegration(
  Directory root, {
  required String directoryName,
  required String packageName,
  required String dartSource,
}) async {
  final integration = Directory(
    '${root.path}/integrations/$directoryName/packages/$packageName',
  );
  await Directory('${integration.path}/lib').create(recursive: true);
  await File(
    '${integration.path}/pubspec.yaml',
  ).writeAsString('name: $packageName\n');
  await File('${integration.path}/lib/main.dart').writeAsString(dartSource);
}
