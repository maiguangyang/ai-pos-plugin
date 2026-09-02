import 'package:flutter/widgets.dart';

import 'lifecycle/plugin_lifecycle.dart';
import 'plugin_context.dart';
import 'plugin_manifest.dart';
import 'plugin_page_context.dart';

/// 插件页面由宿主在自己的导航容器中构建。
typedef AiPosPluginPageBuilder =
    Widget Function(BuildContext context, AiPosPluginPageContext pageContext);

/// 每个第三方业务 package 必须提供的唯一插件入口。
abstract interface class AiPosPlugin {
  AiPosPluginManifest get manifest;
  Map<String, AiPosPluginPageBuilder> get pages;

  Future<void> initialize(
    AiPosPluginContext context,
    AiPosPluginLifecycle lifecycle,
  );
  Future<void> dispose();
}
