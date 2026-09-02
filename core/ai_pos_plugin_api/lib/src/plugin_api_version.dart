import 'package:flutter/foundation.dart';

/// 宿主与第三方插件共同遵守的公共 API 版本。
@immutable
final class AiPosPluginApiVersion {
  const AiPosPluginApiVersion({required this.major, required this.minor})
    : assert(major >= 0),
      assert(minor >= 0);

  final int major;
  final int minor;

  /// 判断当前宿主版本能否满足插件声明的最低版本。
  bool supports(AiPosPluginApiVersion required) {
    if (major == 0 || required.major == 0) {
      return major == required.major && minor == required.minor;
    }
    return major == required.major && minor >= required.minor;
  }

  @override
  bool operator ==(Object other) {
    return other is AiPosPluginApiVersion &&
        other.major == major &&
        other.minor == minor;
  }

  @override
  int get hashCode => Object.hash(major, minor);

  @override
  String toString() => '$major.$minor';
}
