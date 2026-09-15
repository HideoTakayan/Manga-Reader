import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hằng số thiết kế chuẩn (Design Tokens) của ứng dụng
class AppStyle {
  // Border Radius
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusDialog = 20.0;

  // Paddings & Margins
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
}

/// Các chế độ giao diện cá nhân hoá ban đêm & bảo vệ mắt
enum AppThemeMode {
  darkCharcoal,    // Mặc định (Than tối / Charcoal Dark)
  warmAmber,       // Hoàng Hôn (Giấy ấm - Lọc ánh sáng xanh bảo vệ mắt)
  midnightForest,  // Rừng Đêm (Xanh rêu dịu thị giác / Forest Pine)
  midnightNavy,    // Đại Dương (Xanh biển sâu dịu mắt / Deep Navy)
}

extension AppThemeModeX on AppThemeMode {
  String get id => name;

  String get title => switch (this) {
    AppThemeMode.darkCharcoal => 'Charcoal',
    AppThemeMode.warmAmber => 'Amber Dusk',
    AppThemeMode.midnightForest => 'Forest Night',
    AppThemeMode.midnightNavy => 'Deep Ocean',
  };

  String get subtitle => switch (this) {
    AppThemeMode.darkCharcoal => 'Tối chuẩn',
    AppThemeMode.warmAmber => 'Hoàng hôn',
    AppThemeMode.midnightForest => 'Rừng xanh',
    AppThemeMode.midnightNavy => 'Biển đêm',
  };

  String get description => switch (this) {
    AppThemeMode.darkCharcoal => 'Nền than tối tiêu chuẩn · Độ tương phản sắc nét · Phù hợp mọi điều kiện ánh sáng',
    AppThemeMode.warmAmber => 'Lọc ánh sáng xanh · Tone vàng nâu dịu mắt · Lý tưởng để đọc ban đêm',
    AppThemeMode.midnightForest => 'Xanh rêu tự nhiên · Giảm mỏi mắt hiệu quả · Thư giãn thần kinh thị giác',
    AppThemeMode.midnightNavy => 'Xanh dương đêm sâu · Cực kỳ hiện đại · Sang trọng và tinh tế',
  };

  List<String> get tags => switch (this) {
    AppThemeMode.darkCharcoal => ['Mặc định'],
    AppThemeMode.warmAmber => ['Bảo vệ mắt', 'Ban đêm'],
    AppThemeMode.midnightForest => ['Bảo vệ mắt'],
    AppThemeMode.midnightNavy => ['Cao cấp'],
  };

  IconData get icon => switch (this) {
    AppThemeMode.darkCharcoal => Icons.nightlight_round,
    AppThemeMode.warmAmber => Icons.wb_twilight_rounded,
    AppThemeMode.midnightForest => Icons.forest_rounded,
    AppThemeMode.midnightNavy => Icons.water_drop_rounded,
  };

  Color get primaryColor => switch (this) {
    AppThemeMode.darkCharcoal => const Color(0xFFFF5252),
    AppThemeMode.warmAmber => const Color(0xFFFF9800),
    AppThemeMode.midnightForest => const Color(0xFF10B981),
    AppThemeMode.midnightNavy => const Color(0xFF38BDF8),
  };

  Color get backgroundColor => switch (this) {
    AppThemeMode.darkCharcoal => const Color(0xFF121212),
    AppThemeMode.warmAmber => const Color(0xFF181310),
    AppThemeMode.midnightForest => const Color(0xFF0B1412),
    AppThemeMode.midnightNavy => const Color(0xFF0A111C),
  };

  Color get cardColor => switch (this) {
    AppThemeMode.darkCharcoal => const Color(0xFF1E1E1E),
    AppThemeMode.warmAmber => const Color(0xFF241D17),
    AppThemeMode.midnightForest => const Color(0xFF12201D),
    AppThemeMode.midnightNavy => const Color(0xFF101C2E),
  };

  Color get surfaceHighlight => switch (this) {
    AppThemeMode.darkCharcoal => const Color(0xFF2C2C2E),
    AppThemeMode.warmAmber => const Color(0xFF332920),
    AppThemeMode.midnightForest => const Color(0xFF1B2E2A),
    AppThemeMode.midnightNavy => const Color(0xFF1A2A42),
  };
}

/// Bảng màu điểm nhấn (Accent Colors) nổi bật cho giao diện
class AppAccentColor {
  final String id;
  final String label;
  final Color color;

  const AppAccentColor({
    required this.id,
    required this.label,
    required this.color,
  });

  static const List<AppAccentColor> presets = [
    AppAccentColor(id: 'crimson',   label: 'Crimson',   color: Color(0xFFFF334B)),
    AppAccentColor(id: 'violet',    label: 'Violet',    color: Color(0xFFA855F7)),
    AppAccentColor(id: 'cyan',      label: 'Cyan',      color: Color(0xFF00E5FF)),
    AppAccentColor(id: 'emerald',   label: 'Emerald',   color: Color(0xFF10B981)),
    AppAccentColor(id: 'sakura',    label: 'Sakura',    color: Color(0xFFEC4899)),
    AppAccentColor(id: 'amber',     label: 'Amber',     color: Color(0xFFF59E0B)),
    AppAccentColor(id: 'coral',     label: 'Coral',     color: Color(0xFFFF6D00)),
    AppAccentColor(id: 'azure',     label: 'Azure',     color: Color(0xFF38BDF8)),
  ];
}

/// Trạng thái giao diện tổng thể của toàn bộ ứng dụng
class AppThemeState {
  final AppThemeMode mode;
  final Color? customAccentColor;
  final bool usePureBlack;
  final String fontFamily;

  const AppThemeState({
    this.mode = AppThemeMode.darkCharcoal,
    this.customAccentColor,
    this.usePureBlack = false,
    this.fontFamily = 'Default',
  });

  String get title => mode.title;
  String get description => mode.description;
  IconData get icon => mode.icon;

  Color get primaryColor => customAccentColor ?? mode.primaryColor;
  Color get backgroundColor =>
      usePureBlack ? const Color(0xFF000000) : mode.backgroundColor;
  Color get cardColor =>
      usePureBlack ? const Color(0xFF121212) : mode.cardColor;
  Color get surfaceHighlight =>
      usePureBlack ? const Color(0xFF1C1C1E) : mode.surfaceHighlight;

  AppThemeState copyWith({
    AppThemeMode? mode,
    Color? customAccentColor,
    bool clearCustomAccent = false,
    bool? usePureBlack,
    String? fontFamily,
  }) {
    return AppThemeState(
      mode: mode ?? this.mode,
      customAccentColor:
          clearCustomAccent ? null : (customAccentColor ?? this.customAccentColor),
      usePureBlack: usePureBlack ?? this.usePureBlack,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

/// StateNotifier quản lý việc thay đổi và lưu trữ theme state
class ThemeNotifier extends StateNotifier<AppThemeState> {
  static const _prefModeKey = 'app_theme_mode';
  static const _prefAccentKey = 'app_theme_accent_color';
  static const _prefPureBlackKey = 'app_theme_pure_black';
  static const _prefFontKey = 'app_theme_font_family';

  ThemeNotifier() : super(const AppThemeState()) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_prefModeKey);
      final savedAccent = prefs.getInt(_prefAccentKey);
      final savedPureBlack = prefs.getBool(_prefPureBlackKey) ?? false;
      final savedFont = prefs.getString(_prefFontKey) ?? 'Default';

      var mode = AppThemeMode.darkCharcoal;
      if (savedMode != null) {
        mode = AppThemeMode.values.firstWhere(
          (m) => m.name == savedMode,
          orElse: () => AppThemeMode.darkCharcoal,
        );
      }

      Color? accentColor;
      if (savedAccent != null && savedAccent != 0) {
        accentColor = Color(savedAccent);
      }

      state = AppThemeState(
        mode: mode,
        customAccentColor: accentColor,
        usePureBlack: savedPureBlack,
        fontFamily: savedFont,
      );
    } catch (_) {}
  }

  Future<void> setTheme(AppThemeMode mode) async {
    state = state.copyWith(mode: mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefModeKey, mode.name);
    } catch (_) {}
  }

  Future<void> setAccentColor(Color? color) async {
    if (color == null) {
      state = state.copyWith(clearCustomAccent: true);
    } else {
      state = state.copyWith(customAccentColor: color);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (color == null) {
        await prefs.remove(_prefAccentKey);
      } else {
        await prefs.setInt(_prefAccentKey, color.toARGB32());
      }
    } catch (_) {}
  }

  Future<void> setPureBlack(bool enabled) async {
    state = state.copyWith(usePureBlack: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefPureBlackKey, enabled);
    } catch (_) {}
  }

  Future<void> setFontFamily(String fontFamily) async {
    state = state.copyWith(fontFamily: fontFamily);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefFontKey, fontFamily);
    } catch (_) {}
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, AppThemeState>((ref) {
  return ThemeNotifier();
});

// Cấu hình giao diện (Theme) chung cho ứng dụng
class AppTheme {
  /// Sinh ThemeData tương ứng với AppThemeState được chọn
  
  static TextStyle _getTextStyle(String? fontFamily, {Color? color, double? fontSize, FontWeight? fontWeight}) {
    if (fontFamily == null || fontFamily == 'Default') {
      return GoogleFonts.nunito(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
      );
    }
    return TextStyle(
      fontFamily: fontFamily,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
    );
  }

  static ThemeData getTheme(AppThemeState themeState) {
    final bg = themeState.backgroundColor;
    final card = themeState.cardColor;
    final primary = themeState.primaryColor;
    final highlight = themeState.surfaceHighlight;

    final onPrimary = primary.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: themeState.fontFamily == 'Default' ? GoogleFonts.nunito().fontFamily : themeState.fontFamily,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: primary,
        surface: card,
        onPrimary: onPrimary,
        onSecondary: onPrimary,
        onSurface: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: _getTextStyle(themeState.fontFamily, 
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: card,
        margin: const EdgeInsets.all(8),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: highlight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: _getTextStyle(themeState.fontFamily, 
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        constraints: const BoxConstraints(maxWidth: 600),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: _getTextStyle(themeState.fontFamily, color: Colors.white, fontSize: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: highlight,
        contentTextStyle: _getTextStyle(themeState.fontFamily, color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        hintStyle: _getTextStyle(themeState.fontFamily, color: Colors.white38, fontSize: 14),
        labelStyle: _getTextStyle(themeState.fontFamily, color: Colors.white70),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppStyle.radiusMedium),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppStyle.radiusMedium),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppStyle.radiusMedium),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppStyle.radiusMedium),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.0),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.08),
        thickness: 1,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary;
          }
          return Colors.white70;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary.withValues(alpha: 0.4);
          }
          return Colors.white24;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        thumbColor: primary,
        inactiveTrackColor: primary.withValues(alpha: 0.24),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: 0.35),
        selectionHandleColor: primary,
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: primary,
        labelColor: primary,
        unselectedLabelColor: Colors.white60,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textTheme: GoogleFonts.nunitoTextTheme(
        const TextTheme(
          displayLarge: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold),
          displayMedium: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
          displaySmall: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
          headlineMedium: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
          titleLarge: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          titleMedium: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          titleSmall: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(color: Colors.white, fontSize: 16),
          bodyMedium: TextStyle(color: Colors.white70, fontSize: 14),
          bodySmall: TextStyle(color: Colors.white54, fontSize: 12),
          labelLarge: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: primary,
        unselectedItemColor: Colors.white54,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: primary.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: primary);
          }
          return const IconThemeData(color: Colors.white54);
        }),
      ),
    );
  }

  // Fallback dark theme
  static final dark = getTheme(const AppThemeState());
}
