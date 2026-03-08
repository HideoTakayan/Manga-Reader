import 'package:flutter/material.dart';

// UiService: Singleton đơn giản quản lý global UI state.
class UiService {
  UiService._();
  static final instance = UiService._();

  final ValueNotifier<bool> isMainBottomBarVisible = ValueNotifier<bool>(true);

  void setMainBottomBarVisible(bool visible) {
    isMainBottomBarVisible.value = visible;
  }
}
