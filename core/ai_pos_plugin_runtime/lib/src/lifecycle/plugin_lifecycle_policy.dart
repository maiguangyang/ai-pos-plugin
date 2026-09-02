import 'package:flutter/foundation.dart';

@immutable
final class AiPosPluginLifecyclePolicy {
  const AiPosPluginLifecyclePolicy({
    this.initializationTimeout = const Duration(seconds: 30),
    this.disposalTimeout = const Duration(seconds: 10),
  });

  final Duration initializationTimeout;
  final Duration disposalTimeout;
}
