import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:manga_reader/core/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('AppTheme & Theme Engine Tests', () {
    test('AppThemeState defaults to Dark Charcoal with no custom accent and pure black false', () {
      const state = AppThemeState();
      expect(state.mode, AppThemeMode.darkCharcoal);
      expect(state.customAccentColor, isNull);
      expect(state.usePureBlack, isFalse);
      expect(state.primaryColor, state.mode.primaryColor);
      expect(state.backgroundColor, state.mode.backgroundColor);
      expect(state.cardColor, state.mode.cardColor);
    });

    test('Custom Accent Color overrides mode primaryColor', () {
      const customColor = Color(0xFFA855F7); // Cyberpunk Purple
      const state = AppThemeState(
        mode: AppThemeMode.darkCharcoal,
        customAccentColor: customColor,
      );

      expect(state.primaryColor, customColor);
      final theme = AppTheme.getTheme(state);
      expect(theme.colorScheme.primary, customColor);
      expect(theme.floatingActionButtonTheme.backgroundColor, customColor);
    });

    test('usePureBlack forces 0x000000 background for AMOLED OLED displays', () {
      const state = AppThemeState(
        mode: AppThemeMode.midnightNavy,
        usePureBlack: true,
      );

      expect(state.backgroundColor, const Color(0xFF000000));
      final theme = AppTheme.getTheme(state);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
    });

    test('AppThemeState copyWith clears custom accent when requested', () {
      const state = AppThemeState(
        customAccentColor: Color(0xFF00E5FF),
        usePureBlack: true,
      );

      final updated = state.copyWith(clearCustomAccent: true);
      expect(updated.customAccentColor, isNull);
      expect(updated.primaryColor, AppThemeMode.darkCharcoal.primaryColor);
      expect(updated.usePureBlack, isTrue);
    });

    test('AppAccentColor presets have unique IDs and valid colors', () {
      final ids = AppAccentColor.presets.map((a) => a.id).toSet();
      expect(ids.length, AppAccentColor.presets.length);
      for (final preset in AppAccentColor.presets) {
        expect(preset.label, isNotEmpty);
        expect(preset.color.a, greaterThan(0));
      }
    });

    test('All AppThemeMode enum values have non-empty titles, descriptions and colors', () {
      for (final mode in AppThemeMode.values) {
        expect(mode.title, isNotEmpty);
        expect(mode.description, isNotEmpty);
        expect(mode.primaryColor, isNotNull);
        expect(mode.backgroundColor, isNotNull);
        expect(mode.cardColor, isNotNull);
      }
    });
  });
}
