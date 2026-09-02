import 'dart:io';

import 'package:ai_pos_plugin_testkit/src/import_boundary_checker.dart';

void main(List<String> arguments) {
  if (arguments.length != 2 || arguments.first != '--root') {
    stderr.writeln('Usage: check_import_boundaries.dart --root <path>');
    exitCode = 1;
    return;
  }

  final root = Directory(arguments[1]);
  if (!root.existsSync()) {
    stderr.writeln('Plugin root does not exist: ${root.path}');
    exitCode = 1;
    return;
  }

  final violations = const AiPosImportBoundaryChecker().check(root);
  for (final violation in violations) {
    stdout.writeln(
      '${violation.filePath}: forbidden import ${violation.importTarget}',
    );
  }
  if (violations.isNotEmpty) {
    exitCode = 1;
  }
}
