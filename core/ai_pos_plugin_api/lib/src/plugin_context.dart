import 'package:flutter/widgets.dart';

import 'plugin_capability.dart';

/// 宿主传给插件的最小运行上下文。
abstract interface class AiPosPluginContext {
  Locale get locale;
  Set<AiPosCapability> get grantedCapabilities;
}
