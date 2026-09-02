import 'package:flutter/foundation.dart';

import 'plugin.dart';

/// 插件静态合同的稳定问题分类。
enum AiPosPluginContractIssueCode {
  invalidPluginId,
  emptyName,
  invalidPluginVersion,
  emptyPages,
  invalidPagePath,
  missingEntryPage,
}

/// 一条不包含第三方敏感数据的静态合同问题。
@immutable
final class AiPosPluginContractIssue {
  const AiPosPluginContractIssue(this.code, {this.field});

  final AiPosPluginContractIssueCode code;
  final String? field;

  @override
  String toString() => field == null ? code.name : '${code.name}:$field';
}

/// 对第三方公开的确定性 Manifest 与页面合同校验器。
abstract final class AiPosPluginContractValidator {
  static final RegExp _pluginIdPattern = RegExp(
    r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$',
  );
  static final RegExp _pluginVersionPattern = RegExp(r'^\d+\.\d+\.\d+$');
  static final RegExp _whitespacePattern = RegExp(r'\s');

  static List<AiPosPluginContractIssue> validate(AiPosPlugin plugin) {
    final manifest = plugin.manifest;
    final issues = <AiPosPluginContractIssue>[];

    if (!_pluginIdPattern.hasMatch(manifest.id)) {
      issues.add(
        const AiPosPluginContractIssue(
          AiPosPluginContractIssueCode.invalidPluginId,
          field: 'id',
        ),
      );
    }
    if (manifest.name.trim().isEmpty) {
      issues.add(
        const AiPosPluginContractIssue(
          AiPosPluginContractIssueCode.emptyName,
          field: 'name',
        ),
      );
    }
    if (!_pluginVersionPattern.hasMatch(manifest.version)) {
      issues.add(
        const AiPosPluginContractIssue(
          AiPosPluginContractIssueCode.invalidPluginVersion,
          field: 'version',
        ),
      );
    }
    if (plugin.pages.isEmpty) {
      issues.add(
        const AiPosPluginContractIssue(
          AiPosPluginContractIssueCode.emptyPages,
          field: 'pages',
        ),
      );
    }
    for (final pagePath in plugin.pages.keys) {
      if (!_isValidPagePath(pagePath)) {
        issues.add(
          AiPosPluginContractIssue(
            AiPosPluginContractIssueCode.invalidPagePath,
            field: pagePath,
          ),
        );
      }
    }
    if (!plugin.pages.containsKey(manifest.entryPage)) {
      issues.add(
        const AiPosPluginContractIssue(
          AiPosPluginContractIssueCode.missingEntryPage,
          field: 'entryPage',
        ),
      );
    }

    return List<AiPosPluginContractIssue>.unmodifiable(issues);
  }

  static bool _isValidPagePath(String value) {
    return value.length > 1 &&
        value.startsWith('/') &&
        !_whitespacePattern.hasMatch(value);
  }
}
