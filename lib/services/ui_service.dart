import 'package:flutter/material.dart';

class UiService {
  UiService._();
  static final instance = UiService._();

  final ValueNotifier<bool> isMainBottomBarVisible = ValueNotifier<bool>(true);

  void setMainBottomBarVisible(bool visible) {
    isMainBottomBarVisible.value = visible;
  }
}
