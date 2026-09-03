import 'package:flutter/material.dart';
import '../services/level_service.dart';

/// Huy hiệu hiển thị Cấp độ độc giả (Lv. 1 - Lv. 10)
class LevelBadge extends StatelessWidget {
  final int level;
  final double fontSize;
  final bool showTitle;
  final EdgeInsets padding;

  const LevelBadge({
    super.key,
    required this.level,
    this.fontSize = 11,
    this.showTitle = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  });

  @override
  Widget build(BuildContext context) {
    final safeLevel = level.clamp(1, LevelService.maxLevel);
    final levelInfo = LevelService.getLevelInfo(
      LevelService.levelThresholds[safeLevel - 1],
    );

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: levelInfo.gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: safeLevel >= 7
            ? [
                BoxShadow(
                  color: levelInfo.badgeColor.withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            safeLevel == 10
                ? Icons.workspace_premium_rounded
                : safeLevel >= 7
                    ? Icons.auto_awesome
                    : Icons.shield_rounded,
            size: fontSize + 2,
            color: Colors.white,
          ),
          const SizedBox(width: 3),
          Text(
            'Lv.$safeLevel',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
              letterSpacing: 0.2,
            ),
          ),
          if (showTitle) ...[
            const SizedBox(width: 4),
            Text(
              '• ${levelInfo.title}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
                fontSize: fontSize * 0.9,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Khung viền Avatar phát sáng theo Cấp độ độc giả
class LevelAvatarFrame extends StatelessWidget {
  final Widget child;
  final int level;
  final double size;

  const LevelAvatarFrame({
    super.key,
    required this.child,
    required this.level,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    final safeLevel = level.clamp(1, LevelService.maxLevel);
    final levelInfo = LevelService.getLevelInfo(
      LevelService.levelThresholds[safeLevel - 1],
    );

    return Container(
      width: size + 8,
      height: size + 8,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: levelInfo.gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: levelInfo.badgeColor.withValues(alpha: safeLevel >= 7 ? 0.6 : 0.3),
            blurRadius: safeLevel >= 7 ? 12 : 6,
            spreadRadius: safeLevel >= 7 ? 2 : 1,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Thẻ Tiến Trình Cấp Độ & EXP Độc Giả (Dùng trên trang Cá Nhân / Account)
class LevelProgressCard extends StatelessWidget {
  final int exp;

  const LevelProgressCard({super.key, required this.exp});

  @override
  Widget build(BuildContext context) {
    final info = LevelService.getLevelInfo(exp);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: info.badgeColor.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: info.badgeColor.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  LevelBadge(level: info.level, fontSize: 13),
                  const SizedBox(width: 8),
                  Text(
                    info.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                '${info.totalExp} EXP',
                style: TextStyle(
                  color: info.badgeColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: info.progress,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(info.badgeColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                info.isMaxLevel
                    ? '🎉 Đã đạt cấp bậc tối thượng!'
                    : 'Tiến trình: ${(info.progress * 100).toStringAsFixed(1)}%',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              if (!info.isMaxLevel)
                Text(
                  '${info.expInCurrentLevel} / ${info.expRequiredForNextLevel} EXP (Lv.${info.level + 1})',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
            ],
          ),
          const Divider(color: Colors.white12, height: 20),
          Row(
            children: [
              const Icon(Icons.menu_book_rounded, color: Colors.blueAccent, size: 16),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Đọc 1 chap truyện = +10 EXP',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
              Text(
                'Đã đọc ~${(info.totalExp / 10).floor()} chap',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
