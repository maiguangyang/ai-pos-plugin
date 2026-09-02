import 'package:ai_pos_plugin_api/ai_pos_plugin_api.dart';
import 'package:flutter/foundation.dart';

/// Route-scoped close recorder with bounded result retention.
final class FakeAiPosPluginPageContext implements AiPosPluginPageContext {
  FakeAiPosPluginPageContext({this.maxRecordedResults = 20}) {
    if (maxRecordedResults < 0) {
      throw ArgumentError.value(
        maxRecordedResults,
        'maxRecordedResults',
        'must not be negative',
      );
    }
  }

  final int maxRecordedResults;
  final List<Object?> _closeResults = [];
  final _TrackingVisibilityNotifier _visibility = _TrackingVisibilityNotifier(
    AiPosPluginPageVisibility.foreground,
  );
  bool _isActive = true;
  int _closeCount = 0;

  bool get isActive => _isActive;
  int get closeCount => _closeCount;
  List<Object?> get closeResults => List<Object?>.unmodifiable(_closeResults);
  bool get hasVisibilityListeners => _visibility.hasRegisteredListeners;

  @override
  AiPosPluginPageVisibility get visibility => _visibility.value;

  @override
  ValueListenable<AiPosPluginPageVisibility> get visibilityListenable =>
      _visibility;

  void setVisibility(AiPosPluginPageVisibility visibility) {
    if (!_isActive) {
      throw StateError('The page context is no longer active.');
    }
    _visibility.value = visibility;
  }

  @override
  void close({Object? result}) {
    if (!_isActive) {
      return;
    }
    _closeCount += 1;
    if (maxRecordedResults == 0) {
      return;
    }
    if (_closeResults.length == maxRecordedResults) {
      _closeResults.removeAt(0);
    }
    _closeResults.add(result);
  }

  /// Ends the route scope and releases every recorded result reference.
  void invalidate() {
    if (!_isActive) {
      return;
    }
    _isActive = false;
    _closeResults.clear();
    _visibility.dispose();
  }
}

final class _TrackingVisibilityNotifier
    extends ValueNotifier<AiPosPluginPageVisibility> {
  _TrackingVisibilityNotifier(super.value);

  bool get hasRegisteredListeners => hasListeners;
}
