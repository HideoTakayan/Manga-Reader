import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Các chế độ giao diện cá nhân hoá ban đêm & bảo vệ mắt
enum AppThemeMode {
  darkCharcoal,    // Mặc định (Than tối / Charcoal Dark)
  warmAmber,       // Hoàng Hôn (Giấy ấm - Lọc ánh sáng xanh bảo vệ mắt)
  amoledBlack,     // Đen Tuyệt Đối (AMOLED / Siêu tiết kiệm pin)
  midnightForest,  // Rừng Đêm (Xanh rêu dịu thị giác / Forest Pine)
  midnightNavy,    // Đại Dương (Xanh biển sâu dịu mắt / Deep Navy)
}

extension AppThemeModeX on AppThemeMode {
  String get id => name;

  String get title => switch (this) {
    AppThemeMode.darkCharcoal => 'Mặc định (Than tối)',
    AppThemeMode.warmAmber => 'Hoàng Hôn (Giấy ấm)',
    AppThemeMode.amoledBlack => 'Đen Tuyệt Đối (AMOLED)',
    AppThemeMode.midnightForest => 'Rừng Đêm (Xanh rêu)',
    AppThemeMode.midnightNavy => 'Đại Dương (Biển đêm)',
  };

  String get description => switch (this) {
    AppThemeMode.darkCharcoal => 'Tối tiêu chuẩn, độ tương phản sắc nét, cân bằng thị giác',
    AppThemeMode.warmAmber => 'Tone ấm vàng nâu lọc ánh sáng xanh, cực êm dịu khi đọc đêm',
    AppThemeMode.amoledBlack => 'Đen 100% tắt điểm ảnh màn hình OLED, siêu tiết kiệm pin',
    AppThemeMode.midnightForest => 'Tone xanh rêu tự nhiên, làm dịu căng thẳng thần kinh mắt',
    AppThemeMode.midnightNavy => 'Tone xanh biển đêm sâu lắng, hiện đại và sang trọng',
  };

  IconData get icon => switch (this) {
    AppThemeMode.darkCharcoal => Icons.nightlight_round,
    AppThemeMode.warmAmber => Icons.wb_twilight_rounded,
    AppThemeMode.amoledBlack => Icons.contrast_rounded,
    AppThemeMode.midnightForest => Icons.forest_rounded,
    AppThemeMode.midnightNavy => Icons.water_drop_rounded,
  };

  Color get primaryColor => switch (this) {
    AppThemeMode.darkCharcoal => const Color(0xFFFF5252),
    AppThemeMode.warmAmber => const Color(0xFFFF9800),
    AppThemeMode.amoledBlack => const Color(0xFFFF3D00),
    AppThemeMode.midnightForest => const Color(0xFF10B981),
    AppThemeMode.midnightNavy => const Color(0xFF38BDF8),
  };

  Color get backgroundColor => switch (this) {
    AppThemeMode.darkCharcoal => const Color(0xFF121212),
    AppThemeMode.warmAmber => const Color(0xFF181310),
    AppThemeMode.amoledBlack => const Color(0xFF000000),
    AppThemeMode.midnightForest => const Color(0xFF0B1412),
    AppThemeMode.midnightNavy => const Color(0xFF0A111C),
  };

  Color get cardColor => switch (this) {
    AppThemeMode.darkCharcoal => const Color(0xFF1E1E1E),
    AppThemeMode.warmAmber => const Color(0xFF241D17),
    AppThemeMode.amoledBlack => const Color(0xFF121212),
    AppThemeMode.midnightForest => const Color(0xFF12201D),
    AppThemeMode.midnightNavy => const Color(0xFF101C2E),
  };

  Color get surfaceHighlight => switch (this) {
    AppThemeMode.darkCharcoal => const Color(0xFF2C2C2E),
    AppThemeMode.warmAmber => const Color(0xFF332920),
    AppThemeMode.amoledBlack => const Color(0xFF1E1E1E),
    AppThemeMode.midnightForest => const Color(0xFF1B2E2A),
    AppThemeMode.midnightNavy => const Color(0xFF1A2A42),
  };
}

/// StateNotifier quản lý việc thay đổi và lưu trữ theme mode
class ThemeNotifier extends StateNotifier<AppThemeMode> {
  static const _prefKey = 'app_theme_mode';

  ThemeNotifier() : super(AppThemeMode.darkCharcoal) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null) {
        final mode = AppThemeMode.values.firstWhere(
          (m) => m.name == saved,
          orElse: () => AppThemeMode.darkCharcoal,
        );
        state = mode;
      }
    } catch (_) {}
  }

  Future<void> setTheme(AppThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, mode.name);
    } catch (_) {}
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, AppThemeMode>((ref) {
  return ThemeNotifier();
});

// Cấu hình giao diện (Theme) chung cho ứng dụng
class AppTheme {
  /// Sinh ThemeData tương ứng với mode được chọn
  static ThemeData getTheme(AppThemeMode mode) {
    final bg = mode.backgroundColor;
    final card = mode.cardColor;
    final primary = mode.primaryColor;
    final highlight = mode.surfaceHighlight;

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: Colors.white70,
        surface: card,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
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
      dialogTheme: DialogThemeData(backgroundColor: highlight),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white, fontSize: 16),
        bodyMedium: TextStyle(color: Colors.white70, fontSize: 14),
        titleLarge: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 22,
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
  static final dark = getTheme(AppThemeMode.darkCharcoal);
}
