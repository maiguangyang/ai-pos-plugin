import 'dart:io';

import 'package:yaml/yaml.dart';

/// 一条确定性的第三方代码边界违规。
final class AiPosImportBoundaryViolation {
  const AiPosImportBoundaryViolation({
    required this.filePath,
    required this.importTarget,
  });

  final String filePath;
  final String importTarget;
}

/// 扫描正式集成与示例插件的 Dart 导入边界。
final class AiPosImportBoundaryChecker {
  const AiPosImportBoundaryChecker();

  static final RegExp _appPathSegmentPattern = RegExp(
    r'(?:^|/)ai-pos-app(?:/|$)',
  );
  static final RegExp _runtimePathSegmentPattern = RegExp(
    r'(?:^|/)ai_pos_plugin_runtime(?:/|$)',
  );
  static final RegExp _floatingWorkspacePathSegmentPattern = RegExp(
    r'(?:^|/)ai_pos_floating_workspace(?:/|$)',
  );
  static final RegExp _testkitPathSegmentPattern = RegExp(
    r'(?:^|/)ai_pos_plugin_testkit(?:/|$)',
  );

  List<AiPosImportBoundaryViolation> check(Directory root) {
    final integrations = _integrationPackages(root);
    final integrationNames = integrations
        .map((integration) => integration.packageName)
        .whereType<String>()
        .toSet();
    final violations = <AiPosImportBoundaryViolation>[];

    for (final integration in integrations) {
      final currentName = integration.packageName;
      final forbiddenSiblingDirectories = integrations
          .where(
            (candidate) =>
                candidate.directory.path != integration.directory.path,
          )
          .map((candidate) => candidate.directory)
          .toList(growable: false);
      _scanPubspec(
        root: root,
        pubspec: integration.pubspec,
        forbiddenSiblingNames: currentName == null
            ? integrationNames
            : integrationNames.difference({currentName}),
        forbiddenSiblingDirectories: forbiddenSiblingDirectories,
        violations: violations,
      );
      _scanDirectory(
        root: root,
        directory: integration.directory,
        testkitForbiddenDirectory: Directory(
          '${integration.directory.path}${Platform.pathSeparator}lib',
        ),
        forbiddenSiblingNames: currentName == null
            ? integrationNames
            : integrationNames.difference({currentName}),
        forbiddenSiblingDirectories: forbiddenSiblingDirectories,
        violations: violations,
      );
    }

    _scanDirectory(
      root: root,
      directory: Directory(
        '${root.path}${Platform.pathSeparator}'
        'example${Platform.pathSeparator}'
        'plugin_host${Platform.pathSeparator}'
        'packages',
      ),
      forbiddenSiblingNames: const {},
      forbiddenSiblingDirectories: integrations
          .map((integration) => integration.directory)
          .toList(growable: false),
      violations: violations,
    );

    violations.sort((left, right) {
      final fileComparison = left.filePath.compareTo(right.filePath);
      return fileComparison != 0
          ? fileComparison
          : left.importTarget.compareTo(right.importTarget);
    });
    return List<AiPosImportBoundaryViolation>.unmodifiable(violations);
  }

  List<({Directory directory, File pubspec, String? packageName})>
  _integrationPackages(Directory root) {
    final integrationsDirectory = Directory(
      '${root.path}${Platform.pathSeparator}integrations',
    );
    if (!integrationsDirectory.existsSync()) {
      return const [];
    }

    final packages =
        <({Directory directory, File pubspec, String? packageName})>[];
    final workspaces =
        integrationsDirectory
            .listSync(followLinks: false)
            .whereType<Directory>()
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    for (final workspace in workspaces) {
      final packagesDirectory = Directory(
        '${workspace.path}${Platform.pathSeparator}packages',
      );
      if (!packagesDirectory.existsSync()) {
        continue;
      }
      final directories =
          packagesDirectory
              .listSync(followLinks: false)
              .whereType<Directory>()
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      for (final directory in directories) {
        final pubspec = File(
          '${directory.path}${Platform.pathSeparator}pubspec.yaml',
        );
        if (!pubspec.existsSync()) {
          continue;
        }
        String? packageName;
        try {
          final yaml = loadYaml(pubspec.readAsStringSync());
          final name = yaml is YamlMap ? yaml['name'] : null;
          packageName = name is String ? name : null;
        } catch (_) {
          packageName = null;
        }
        packages.add((
          directory: directory,
          pubspec: pubspec,
          packageName: packageName,
        ));
      }
    }
    return packages;
  }

  void _scanPubspec({
    required Directory root,
    required File pubspec,
    required Set<String> forbiddenSiblingNames,
    required List<Directory> forbiddenSiblingDirectories,
    required List<AiPosImportBoundaryViolation> violations,
  }) {
    final Object? yaml;
    try {
      yaml = loadYaml(pubspec.readAsStringSync());
    } catch (_) {
      return;
    }
    if (yaml is! YamlMap) {
      return;
    }
    const sections = [
      'dependencies',
      'dev_dependencies',
      'dependency_overrides',
    ];
    for (final sectionName in sections) {
      final section = yaml[sectionName];
      if (section is! YamlMap) {
        continue;
      }
      for (final entry in section.entries) {
        final dependencyName = entry.key;
        if (dependencyName is! String) {
          continue;
        }
        final forbidTestkit = sectionName != 'dev_dependencies';
        final forbiddenByName =
            dependencyName == 'ai_pos_app' ||
            dependencyName == 'ai_pos_plugin_runtime' ||
            dependencyName == 'ai_pos_floating_workspace' ||
            (forbidTestkit && dependencyName == 'ai_pos_plugin_testkit') ||
            forbiddenSiblingNames.contains(dependencyName);
        final value = entry.value;
        final dependencyPath = value is YamlMap ? value['path'] : null;
        final forbiddenByPath =
            dependencyPath is String &&
            (_appPathSegmentPattern.hasMatch(dependencyPath) ||
                _runtimePathSegmentPattern.hasMatch(dependencyPath) ||
                _floatingWorkspacePathSegmentPattern.hasMatch(dependencyPath) ||
                (forbidTestkit &&
                    _testkitPathSegmentPattern.hasMatch(dependencyPath)) ||
                _resolvesInside(
                  sourceFile: pubspec,
                  target: dependencyPath,
                  directories: forbiddenSiblingDirectories,
                ));
        if (forbiddenByName || forbiddenByPath) {
          violations.add(
            AiPosImportBoundaryViolation(
              filePath: _relativePath(root, pubspec),
              importTarget: 'package:$dependencyName',
            ),
          );
        }
      }
    }
  }

  void _scanDirectory({
    required Directory root,
    required Directory directory,
    Directory? testkitForbiddenDirectory,
    required Set<String> forbiddenSiblingNames,
    required List<Directory> forbiddenSiblingDirectories,
    required List<AiPosImportBoundaryViolation> violations,
  }) {
    if (!directory.existsSync()) {
      return;
    }
    final files =
        directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final target in _DartDirectiveScanner(source).uris()) {
        if (_isForbidden(
          sourceFile: file,
          target: target,
          forbidTestkit:
              testkitForbiddenDirectory != null &&
              _isInside(file, testkitForbiddenDirectory),
          forbiddenSiblingNames: forbiddenSiblingNames,
          forbiddenSiblingDirectories: forbiddenSiblingDirectories,
        )) {
          violations.add(
            AiPosImportBoundaryViolation(
              filePath: _relativePath(root, file),
              importTarget: target,
            ),
          );
        }
      }
    }
  }

  bool _isForbidden({
    required File sourceFile,
    required String target,
    required bool forbidTestkit,
    required Set<String> forbiddenSiblingNames,
    required List<Directory> forbiddenSiblingDirectories,
  }) {
    if (target.startsWith('package:ai_pos_app/') ||
        target.startsWith('package:ai_pos_plugin_runtime/') ||
        target.startsWith('package:ai_pos_floating_workspace/') ||
        (forbidTestkit &&
            target.startsWith('package:ai_pos_plugin_testkit/'))) {
      return true;
    }
    if (!target.contains(':') &&
        (_appPathSegmentPattern.hasMatch(target) ||
            _runtimePathSegmentPattern.hasMatch(target) ||
            _floatingWorkspacePathSegmentPattern.hasMatch(target) ||
            (forbidTestkit && _testkitPathSegmentPattern.hasMatch(target)))) {
      return true;
    }
    if (!target.startsWith('package:')) {
      if (_resolvesInside(
        sourceFile: sourceFile,
        target: target,
        directories: forbiddenSiblingDirectories,
      )) {
        return true;
      }
      return false;
    }
    final separator = target.indexOf('/');
    final packageName = separator == -1
        ? target.substring('package:'.length)
        : target.substring('package:'.length, separator);
    return forbiddenSiblingNames.contains(packageName);
  }

  bool _isInside(File file, Directory directory) {
    final directoryPath = directory.absolute.path;
    final prefix = directoryPath.endsWith(Platform.pathSeparator)
        ? directoryPath
        : '$directoryPath${Platform.pathSeparator}';
    return file.absolute.path.startsWith(prefix);
  }

  bool _resolvesInside({
    required File sourceFile,
    required String target,
    required List<Directory> directories,
  }) {
    final targetUri = Uri.tryParse(target);
    if (targetUri == null || targetUri.hasScheme) {
      return false;
    }
    final resolvedUri = sourceFile.parent.uri.resolveUri(targetUri);
    if (resolvedUri.scheme != 'file') {
      return false;
    }
    final resolvedPath = File.fromUri(resolvedUri).absolute.path;
    for (final directory in directories) {
      final directoryPath = directory.absolute.path;
      final prefix = directoryPath.endsWith(Platform.pathSeparator)
          ? directoryPath
          : '$directoryPath${Platform.pathSeparator}';
      if (resolvedPath == directoryPath || resolvedPath.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  String _relativePath(Directory root, File file) {
    final prefix = '${root.absolute.path}${Platform.pathSeparator}';
    final absolutePath = file.absolute.path;
    final relativePath = absolutePath.startsWith(prefix)
        ? absolutePath.substring(prefix.length)
        : absolutePath;
    return relativePath.replaceAll(Platform.pathSeparator, '/');
  }
}

/// Extracts URI literals from real import/export/part directives while
/// skipping comments and non-directive strings.
final class _DartDirectiveScanner {
  const _DartDirectiveScanner(this.source);

  final String source;

  Iterable<String> uris() sync* {
    var index = 0;
    while (index < source.length) {
      final skipped = _skipCommentOrString(index);
      if (skipped != null) {
        index = skipped;
        continue;
      }

      final keywordLength = _directiveKeywordLength(index);
      if (keywordLength == null) {
        index += 1;
        continue;
      }

      index += keywordLength;
      while (index < source.length) {
        final commentEnd = _skipComment(index);
        if (commentEnd != null) {
          index = commentEnd;
          continue;
        }
        final literal = _readString(index);
        if (literal != null) {
          yield literal.value;
          index = literal.end;
          continue;
        }
        if (source.codeUnitAt(index) == _semicolon) {
          index += 1;
          break;
        }
        index += 1;
      }
    }
  }

  int? _directiveKeywordLength(int index) {
    for (final keyword in const ['import', 'export', 'part']) {
      if (!source.startsWith(keyword, index)) {
        continue;
      }
      final before = index == 0 ? null : source.codeUnitAt(index - 1);
      final afterIndex = index + keyword.length;
      final after = afterIndex == source.length
          ? null
          : source.codeUnitAt(afterIndex);
      if (!_isIdentifierCharacter(before) && !_isIdentifierCharacter(after)) {
        return keyword.length;
      }
    }
    return null;
  }

  int? _skipCommentOrString(int index) {
    final commentEnd = _skipComment(index);
    if (commentEnd != null) {
      return commentEnd;
    }
    return _readString(index)?.end;
  }

  int? _skipComment(int index) {
    if (index + 1 >= source.length || source.codeUnitAt(index) != _slash) {
      return null;
    }
    final next = source.codeUnitAt(index + 1);
    if (next == _slash) {
      final lineEnd = source.indexOf('\n', index + 2);
      return lineEnd == -1 ? source.length : lineEnd + 1;
    }
    if (next != _asterisk) {
      return null;
    }

    var depth = 1;
    var cursor = index + 2;
    while (cursor < source.length && depth > 0) {
      if (cursor + 1 < source.length &&
          source.codeUnitAt(cursor) == _slash &&
          source.codeUnitAt(cursor + 1) == _asterisk) {
        depth += 1;
        cursor += 2;
      } else if (cursor + 1 < source.length &&
          source.codeUnitAt(cursor) == _asterisk &&
          source.codeUnitAt(cursor + 1) == _slash) {
        depth -= 1;
        cursor += 2;
      } else {
        cursor += 1;
      }
    }
    return cursor;
  }

  ({String value, int end})? _readString(int index) {
    var cursor = index;
    var isRaw = false;
    if (_isRawPrefix(cursor)) {
      isRaw = true;
      cursor += 1;
    }
    if (cursor >= source.length || !_isQuote(source.codeUnitAt(cursor))) {
      return null;
    }

    final quote = source.codeUnitAt(cursor);
    final isTriple =
        cursor + 2 < source.length &&
        source.codeUnitAt(cursor + 1) == quote &&
        source.codeUnitAt(cursor + 2) == quote;
    cursor += isTriple ? 3 : 1;
    final value = StringBuffer();

    while (cursor < source.length) {
      if (_isClosingQuote(cursor, quote, isTriple)) {
        return (value: value.toString(), end: cursor + (isTriple ? 3 : 1));
      }
      final character = source.codeUnitAt(cursor);
      if (!isRaw && character == _backslash) {
        final escape = _readEscape(cursor);
        value.write(escape.value);
        cursor = escape.end;
      } else {
        value.writeCharCode(character);
        cursor += 1;
      }
    }

    return (value: value.toString(), end: source.length);
  }

  ({String value, int end}) _readEscape(int index) {
    if (index + 1 >= source.length) {
      return (value: r'\', end: source.length);
    }
    final escaped = source.codeUnitAt(index + 1);
    final simple = switch (escaped) {
      110 => '\n',
      114 => '\r',
      116 => '\t',
      98 => '\b',
      102 => '\f',
      118 => '\v',
      _ => null,
    };
    if (simple != null) {
      return (value: simple, end: index + 2);
    }
    if (escaped == 120) {
      return _readFixedHexEscape(index, digits: 2);
    }
    if (escaped == 117) {
      return _readUnicodeEscape(index);
    }
    return (value: String.fromCharCode(escaped), end: index + 2);
  }

  ({String value, int end}) _readFixedHexEscape(
    int index, {
    required int digits,
  }) {
    final start = index + 2;
    final end = start + digits;
    if (end > source.length) {
      return (value: source.substring(index), end: source.length);
    }
    final value = int.tryParse(source.substring(start, end), radix: 16);
    return value == null
        ? (value: source.substring(index, end), end: end)
        : (value: String.fromCharCode(value), end: end);
  }

  ({String value, int end}) _readUnicodeEscape(int index) {
    final valueStart = index + 2;
    if (valueStart < source.length &&
        source.codeUnitAt(valueStart) == _leftBrace) {
      final close = source.indexOf('}', valueStart + 1);
      if (close != -1) {
        final value = int.tryParse(
          source.substring(valueStart + 1, close),
          radix: 16,
        );
        if (value != null && value <= 0x10ffff) {
          return (value: String.fromCharCode(value), end: close + 1);
        }
      }
      return (value: r'\u', end: valueStart);
    }
    return _readFixedHexEscape(index, digits: 4);
  }

  bool _isRawPrefix(int index) {
    if (index + 1 >= source.length) {
      return false;
    }
    final character = source.codeUnitAt(index);
    return (character == 114 || character == 82) &&
        _isQuote(source.codeUnitAt(index + 1));
  }

  bool _isClosingQuote(int index, int quote, bool isTriple) {
    if (source.codeUnitAt(index) != quote) {
      return false;
    }
    return !isTriple ||
        (index + 2 < source.length &&
            source.codeUnitAt(index + 1) == quote &&
            source.codeUnitAt(index + 2) == quote);
  }

  static bool _isIdentifierCharacter(int? character) {
    if (character == null) {
      return false;
    }
    return character == 36 ||
        character == 95 ||
        character >= 48 && character <= 57 ||
        character >= 65 && character <= 90 ||
        character >= 97 && character <= 122;
  }

  static bool _isQuote(int character) =>
      character == _singleQuote || character == _doubleQuote;

  static const int _backslash = 92;
  static const int _singleQuote = 39;
  static const int _doubleQuote = 34;
  static const int _slash = 47;
  static const int _asterisk = 42;
  static const int _semicolon = 59;
  static const int _leftBrace = 123;
}
