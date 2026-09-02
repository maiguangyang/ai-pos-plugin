import 'dart:ui' as ui;

import 'package:flutter/material.dart';

typedef FloatingSnapshotBuilder =
    Widget Function({Key? key, required BoxFit fit});

abstract interface class FloatingSnapshot {
  factory FloatingSnapshot.memory({
    required int width,
    required int height,
    required FloatingSnapshotBuilder builder,
    required VoidCallback onDispose,
  }) = _MemoryFloatingSnapshot;

  factory FloatingSnapshot.image(ui.Image image) =
      _MemoryFloatingSnapshot.image;

  int get width;
  int get height;
  int get estimatedBytes;
  bool get isDisposed;

  Widget build({Key? key, BoxFit fit = BoxFit.cover});
  void dispose();
}

final class _MemoryFloatingSnapshot implements FloatingSnapshot {
  _MemoryFloatingSnapshot({
    required this.width,
    required this.height,
    required FloatingSnapshotBuilder builder,
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

  factory _MemoryFloatingSnapshot.image(ui.Image image) {
    return _MemoryFloatingSnapshot(
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

  @override
  final int width;
  @override
  final int height;
  final FloatingSnapshotBuilder _builder;
  VoidCallback? _onDispose;

  @override
  int get estimatedBytes => width * height * 4;

  @override
  bool get isDisposed => _onDispose == null;

  @override
  Widget build({Key? key, BoxFit fit = BoxFit.cover}) {
    if (isDisposed) {
      throw StateError('The floating snapshot is disposed.');
    }
    return _builder(key: key, fit: fit);
  }

  @override
  void dispose() {
    final release = _onDispose;
    if (release == null) {
      return;
    }
    _onDispose = null;
    release();
  }
}
