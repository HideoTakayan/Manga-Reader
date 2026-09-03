import 'package:flutter/material.dart';

/// Huy hiệu Top BXH Diễn Đàn & Bảng Vinh Danh (Top 1 -> Top 50)
class VipRankBadge extends StatelessWidget {
  final int rank;
  final double fontSize;

  const VipRankBadge({
    super.key,
    required this.rank,
    this.fontSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    if (rank <= 0 || rank > 50) return const SizedBox.shrink();

    String label;
    IconData icon;
    List<Color> gradientColors;
    Color glowColor;
    Color textColor;

    if (rank == 1) {
      label = '👑 Top 1 Chí Tôn';
      icon = Icons.workspace_premium_rounded;
      gradientColors = const [Color(0xFFFFEA00), Color(0xFFFF9100), Color(0xFFFF3D00)];
      glowColor = Colors.amber;
      textColor = Colors.black87;
    } else if (rank == 2) {
      label = '🥈 Top 2 Bạch Kim';
      icon = Icons.shield_rounded;
      gradientColors = const [Color(0xFFFFFFFF), Color(0xFFB0BEC5), Color(0xFF607D8B)];
      glowColor = Colors.blueGrey;
      textColor = Colors.black87;
    } else if (rank == 3) {
      label = '🥉 Top 3 Hoàng Đồng';
      icon = Icons.military_tech_rounded;
      gradientColors = const [Color(0xFFFFAB91), Color(0xFFFF7043), Color(0xFFD84315)];
      glowColor = Colors.deepOrange;
      textColor = Colors.white;
    } else if (rank <= 5) {
      label = '💎 Top $rank Kim Cương';
      icon = Icons.diamond_rounded;
      gradientColors = const [Color(0xFF80DEEA), Color(0xFF00E5FF), Color(0xFF0091EA)];
      glowColor = Colors.cyanAccent;
      textColor = Colors.black87;
    } else if (rank <= 10) {
      label = '🌟 Top $rank Tinh Anh';
      icon = Icons.stars_rounded;
      gradientColors = const [Color(0xFFEA80FC), Color(0xFFE040FB), Color(0xFF7B1FA2)];
      glowColor = Colors.purpleAccent;
      textColor = Colors.white;
    } else if (rank <= 20) {
      label = '⚔️ Top $rank Cao Thủ';
      icon = Icons.local_fire_department_rounded;
      gradientColors = const [Color(0xFFFF8A80), Color(0xFFFF5252), Color(0xFFC62828)];
      glowColor = Colors.redAccent;
      textColor = Colors.white;
    } else {
      label = '🛡️ Top $rank Tiên Phong';
      icon = Icons.verified_user_rounded;
      gradientColors = const [Color(0xFFB9F6CA), Color(0xFF00E676), Color(0xFF2E7D32)];
      glowColor = Colors.greenAccent;
      textColor = Colors.black87;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: rank <= 3 ? 0.6 : 0.35),
            blurRadius: rank == 1 ? 8 : (rank <= 5 ? 6 : 4),
            spreadRadius: rank == 1 ? 1.5 : 0.5,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: fontSize + 3, color: textColor),
          const SizedBox(width: 3.5),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w900,
              fontSize: fontSize,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Khung viền Avatar có hiệu ứng Top BXH (Vương miện cho Top 1, Kim cương cho Top 4-5, Tinh anh cho Top 10,...)
class VipAvatarFrame extends StatelessWidget {
  final Widget child;
  final int rank;
  final double radius;

  const VipAvatarFrame({
    super.key,
    required this.child,
    required this.rank,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    if (rank <= 0 || rank > 50) return child;

    List<Color> borderGradient;
    Color glowColor;
    String? crownIcon;

    if (rank == 1) {
      borderGradient = const [Color(0xFFFFEA00), Color(0xFFFF9100), Color(0xFFFF3D00)];
      glowColor = Colors.amber;
      crownIcon = '👑';
    } else if (rank == 2) {
      borderGradient = const [Color(0xFFFFFFFF), Color(0xFFB0BEC5), Color(0xFF607D8B)];
      glowColor = Colors.blueGrey;
      crownIcon = '🥈';
    } else if (rank == 3) {
      borderGradient = const [Color(0xFFFFAB91), Color(0xFFFF7043), Color(0xFFD84315)];
      glowColor = Colors.deepOrange;
      crownIcon = '🥉';
    } else if (rank <= 5) {
      borderGradient = const [Color(0xFF80DEEA), Color(0xFF00E5FF), Color(0xFF0091EA)];
      glowColor = Colors.cyanAccent;
      crownIcon = '💎';
    } else if (rank <= 10) {
      borderGradient = const [Color(0xFFEA80FC), Color(0xFFE040FB), Color(0xFF7B1FA2)];
      glowColor = Colors.purpleAccent;
      crownIcon = '🌟';
    } else if (rank <= 20) {
      borderGradient = const [Color(0xFFFF8A80), Color(0xFFFF5252), Color(0xFFC62828)];
      glowColor = Colors.redAccent;
      crownIcon = '⚔️';
    } else {
      borderGradient = const [Color(0xFFB9F6CA), Color(0xFF00E676), Color(0xFF2E7D32)];
      glowColor = Colors.greenAccent;
      crownIcon = '🛡️';
    }

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: borderGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: glowColor.withValues(alpha: rank <= 3 ? 0.7 : 0.4),
                blurRadius: rank == 1 ? 10 : 6,
                spreadRadius: rank == 1 ? 2 : 1,
              ),
            ],
          ),
          child: child,
        ),
        if (rank <= 10)
          Positioned(
            top: -7,
            child: Text(
              crownIcon,
              style: TextStyle(fontSize: radius * 0.75),
            ),
          ),
      ],
    );
  }
}

/// Dải Banner Vinh Danh VIP đặt trên đầu Thẻ Bài Viết (ForumPostCard)
class VipPostRibbon extends StatelessWidget {
  final int rank;

  const VipPostRibbon({super.key, required this.rank});

  @override
  Widget build(BuildContext context) {
    if (rank <= 0 || rank > 50) return const SizedBox.shrink();

    String title;
    List<Color> gradientColors;
    Color glowColor;
    Color textColor = Colors.black87;

    if (rank == 1) {
      title = '🏆 ĐỆ NHẤT CHÍ TÔN • TOP 1 SERVER';
      gradientColors = const [Color(0xFFFFEA00), Color(0xFFFF9100), Color(0xFFFF3D00)];
      glowColor = Colors.amber;
      textColor = Colors.black87;
    } else if (rank == 2) {
      title = '🥈 Á QUÂN BẠCH KIM • TOP 2 SERVER';
      gradientColors = const [Color(0xFFFFFFFF), Color(0xFFB0BEC5), Color(0xFF78909C)];
      glowColor = Colors.blueGrey;
      textColor = Colors.black87;
    } else if (rank == 3) {
      title = '🥉 QUÝ QUÂN HOÀNG ĐỒNG • TOP 3 SERVER';
      gradientColors = const [Color(0xFFFFAB91), Color(0xFFFF7043), Color(0xFFD84315)];
      glowColor = Colors.deepOrange;
      textColor = Colors.white;
    } else if (rank <= 5) {
      title = '💎 BẬC THẦY KIM CƯƠNG • TOP $rank SERVER';
      gradientColors = const [Color(0xFF80DEEA), Color(0xFF00E5FF), Color(0xFF0091EA)];
      glowColor = Colors.cyanAccent;
      textColor = Colors.black87;
    } else if (rank <= 10) {
      title = '🌟 TINH ANH TOÀN SERVER • TOP $rank';
      gradientColors = const [Color(0xFFEA80FC), Color(0xFFE040FB), Color(0xFF7B1FA2)];
      glowColor = Colors.purpleAccent;
      textColor = Colors.white;
    } else if (rank <= 20) {
      title = '⚔️ CAO THỦ CHIẾN TRANH • TOP $rank';
      gradientColors = const [Color(0xFFFF8A80), Color(0xFFFF5252), Color(0xFFC62828)];
      glowColor = Colors.redAccent;
      textColor = Colors.white;
    } else {
      title = '🛡️ TIÊN PHONG BẤT DIỆT • TOP $rank';
      gradientColors = const [Color(0xFFB9F6CA), Color(0xFF00E676), Color(0xFF2E7D32)];
      glowColor = Colors.greenAccent;
      textColor = Colors.black87;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, size: 13, color: textColor),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.auto_awesome, size: 13, color: textColor),
        ],
      ),
    );
  }
}
