import 'package:flutter/foundation.dart';

import 'plugin_page_visibility.dart';

/// 宿主为一次插件页面会话提供的可见性与关闭能力。
abstract interface class AiPosPluginPageContext {
  AiPosPluginPageVisibility get visibility;

  ValueListenable<AiPosPluginPageVisibility> get visibilityListenable;

  void close({Object? result});
}
