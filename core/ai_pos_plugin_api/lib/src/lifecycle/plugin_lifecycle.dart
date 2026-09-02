/// 插件初始化与宿主关闭共同使用的合作式取消信号。
abstract interface class AiPosPluginLifecycle {
  bool get isCancellationRequested;

  Future<void> get cancellationRequested;

  void throwIfCancellationRequested();
}

/// 插件主动检查生命周期时得到的稳定取消异常。
final class AiPosPluginCancellationException implements Exception {
  const AiPosPluginCancellationException();

  @override
  String toString() => 'AiPosPluginCancellationException';
}
