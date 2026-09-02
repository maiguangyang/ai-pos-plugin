import 'dart:ui' as ui;

import 'package:flutter/material.dart';

typedef AiPosPluginSnapshotBuilder =
    Widget Function({Key? key, required BoxFit fit});

/// Owns one in-memory snapshot and releases its pixels exactly once.
final class AiPosPluginSnapshot {
  AiPosPluginSnapshot({
    required this.width,
    required this.height,
    required AiPosPluginSnapshotBuilder builder,
    required VoidCallback onDispose,
  }) : _builder = builder,
       _onDispose = onDispose {
    if (width <= 0) {
      throw ArgumentError.value(width, 'width', 'must be positive');
    }
    if (height <= 0) {
      throw ArgumentError.value(height, 'height', 'must be positive');
    }
  }

  factory AiPosPluginSnapshot.image(ui.Image image) {
    return AiPosPluginSnapshot(
      width: image.width,
      height: image.height,
      builder: ({key, required fit}) => RawImage(
        key: key,
        image: image,
        fit: fit,
        filterQuality: FilterQuality.low,
      ),
      onDispose: image.dispose,
    );
  }

  final int width;
  final int height;
  final AiPosPluginSnapshotBuilder _builder;
  VoidCallback? _onDispose;

  int get estimatedBytes => width * height * 4;
  bool get isDisposed => _onDispose == null;

  Widget build({Key? key, BoxFit fit = BoxFit.cover}) {
    if (isDisposed) {
      throw StateError('The plugin snapshot is disposed.');
    }
    return _builder(key: key, fit: fit);
  }

  void dispose() {
    final release = _onDispose;
    if (release == null) {
      return;
    }
    _onDispose = null;
    release();
  }
}
