import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/widgets/vip_leaderboard_flair.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VIP Leaderboard Flair Widget Tests', () {
    testWidgets('VipRankBadge displays Top 1, Top 2, Top 3, and Top 10 badges',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                VipRankBadge(rank: 1),
                VipRankBadge(rank: 2),
                VipRankBadge(rank: 3),
                VipRankBadge(rank: 7),
                VipRankBadge(rank: 15),
                VipRankBadge(rank: 55), // Should not render (rank > 50)
              ],
            ),
          ),
        ),
      );

      expect(find.text('👑 Top 1 Chí Tôn'), findsOneWidget);
      expect(find.text('🥈 Top 2 Bạch Kim'), findsOneWidget);
      expect(find.text('🥉 Top 3 Hoàng Đồng'), findsOneWidget);
      expect(find.text('🌟 Top 7 Tinh Anh'), findsOneWidget);
      expect(find.text('⚔️ Top 15 Cao Thủ'), findsOneWidget);
      expect(find.textContaining('Top 55'), findsNothing);
    });

    testWidgets('VipPostRibbon displays holographic title for Top ranks',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                VipPostRibbon(rank: 1),
                VipPostRibbon(rank: 2),
                VipPostRibbon(rank: 3),
              ],
            ),
          ),
        ),
      );

      expect(find.text('🏆 ĐỆ NHẤT CHÍ TÔN • TOP 1 SERVER'), findsOneWidget);
      expect(find.text('🥈 Á QUÂN BẠCH KIM • TOP 2 SERVER'), findsOneWidget);
      expect(find.text('🥉 QUÝ QUÂN HOÀNG ĐỒNG • TOP 3 SERVER'), findsOneWidget);
    });

    testWidgets('VipAvatarFrame renders crown and child avatar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VipAvatarFrame(
              rank: 1,
              radius: 20,
              child: CircleAvatar(child: Text('A')),
            ),
          ),
        ),
      );

      expect(find.text('👑'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
    });
  });
}
