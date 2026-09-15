import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../services/level_service.dart';
import '../../../widgets/level_badge.dart';
import '../../../widgets/vip_leaderboard_flair.dart';
import 'services/leaderboard_service.dart';

/// Trang Bảng Xếp Hạng Đua Top Độc Giả Toàn Server (Hall of Fame)
class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  int _selectedCategory = 0; // 0: Top EXP & Cấp độ, 1: Top Cày Chap
  // Stream được lưu ở state để tránh tạo mới mỗi lần build() chạy lại
  // (tránh StreamBuilder reconnect → flicker mỗi lần setState)
  late Stream<List<LeaderboardUser>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = LeaderboardService.instance.streamTopExpUsers();
  }

  void _switchCategory(int index) {
    if (_selectedCategory == index) return;
    setState(() {
      _selectedCategory = index;
      _stream = index == 0
          ? LeaderboardService.instance.streamTopExpUsers()
          : LeaderboardService.instance.streamTopChaptersUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final stream = _stream;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: StreamBuilder<List<LeaderboardUser>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data ?? [];
          final top1 = users.isNotEmpty ? users[0] : null;
          final top2 = users.length > 1 ? users[1] : null;
          final top3 = users.length > 2 ? users[2] : null;
          final restUsers = users.length > 3 ? users.sublist(3) : <LeaderboardUser>[];

          // Tìm vị trí của người dùng hiện tại
          LeaderboardUser? myEntry;
          if (currentUserId != null) {
            for (final u in users) {
              if (u.uid == currentUserId) {
                myEntry = u;
                break;
              }
            }
          }

          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  // Category Selector Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildCategoryTab(
                              index: 0,
                              title: '🔥 Top Cấp Bậc & EXP',
                              icon: Icons.local_fire_department_rounded,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildCategoryTab(
                              index: 1,
                              title: '📖 Siêu Cày Chap',
                              icon: Icons.auto_stories_rounded,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Top 3 Podium
                  if (users.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildPodium(top1: top1, top2: top2, top3: top3),
                    ),

                  // Danh sách hạng 4 trở đi
                  if (restUsers.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final user = restUsers[index];
                            final isMe = user.uid == currentUserId;
                            return _buildRankRow(user, isMe);
                          },
                          childCount: restUsers.length,
                        ),
                      ),
                    )
                  else if (users.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.amber.withValues(alpha: 0.25),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.emoji_events_outlined,
                                  size: 48,
                                  color: Colors.amber,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Bảng xếp hạng đang cập nhật',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Hãy đọc truyện và tham gia diễn đàn để nhận điểm EXP và trở thành độc giả đầu tiên ghi danh trên bảng vàng!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    const SliverToBoxAdapter(child: SizedBox(height: 90)),
                ],
              ),

              // Bottom Sticky "My Rank" Bar
              Positioned(
                bottom: 12,
                left: 16,
                right: 16,
                child: _buildMyRankBar(myEntry),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCategoryTab({
    required int index,
    required String title,
    required IconData icon,
  }) {
    final isSelected = _selectedCategory == index;
    return GestureDetector(
      onTap: () => _switchCategory(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.white10,
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPodium({
    LeaderboardUser? top1,
    LeaderboardUser? top2,
    LeaderboardUser? top3,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.withValues(alpha: 0.12),
            Colors.purple.withValues(alpha: 0.08),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Top 2 (Bạc)
          Expanded(
            child: top2 != null
                ? _buildPodiumItem(
                    user: top2,
                    rank: 2,
                    color: const Color(0xFFC0C0C0),
                    trophy: '🥈',
                    height: 140,
                  )
                : const SizedBox(),
          ),
          const SizedBox(width: 8),
          // Top 1 (Vàng - Trung tâm cao nhất)
          Expanded(
            child: top1 != null
                ? _buildPodiumItem(
                    user: top1,
                    rank: 1,
                    color: const Color(0xFFFFD700),
                    trophy: '👑',
                    height: 175,
                    isChampion: true,
                  )
                : const SizedBox(),
          ),
          const SizedBox(width: 8),
          // Top 3 (Đồng)
          Expanded(
            child: top3 != null
                ? _buildPodiumItem(
                    user: top3,
                    rank: 3,
                    color: const Color(0xFFCD7F32),
                    trophy: '🥉',
                    height: 125,
                  )
                : const SizedBox(),
          ),
        ],
      ),
    );
  }

  Widget _buildPodiumItem({
    required LeaderboardUser user,
    required int rank,
    required Color color,
    required String trophy,
    required double height,
    bool isChampion = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(trophy, style: TextStyle(fontSize: isChampion ? 26 : 22)),
        const SizedBox(height: 2),
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: isChampion ? 3 : 2),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: isChampion ? 12 : 6,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: isChampion ? 32 : 26,
                backgroundImage: user.avatarUrl.isNotEmpty
                    ? CachedNetworkImageProvider(user.avatarUrl)
                    : null,
                child: user.avatarUrl.isEmpty
                    ? Text(
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: isChampion ? 20 : 16,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '#$rank',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          user.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isChampion ? 13 : 11.5,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        LevelBadge(level: user.level, fontSize: isChampion ? 10 : 8.5),
        const SizedBox(height: 3),
        Text(
          _selectedCategory == 0
              ? '${user.exp} EXP'
              : '${user.claimedChaptersCount} chap',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: isChampion ? 12 : 10.5,
          ),
        ),
      ],
    );
  }

  Widget _buildRankRow(LeaderboardUser user, bool isMe) {
    // Màu sắc, background và badge phân cấp riêng biệt theo từng Rank Tier
    Color rankBorderColor;
    Color rankBgColor;
    Widget rankIndicator;

    if (user.rank == 1) {
      rankBorderColor = const Color(0xFFFFD700).withValues(alpha: 0.6);
      rankBgColor = const Color(0xFF2C2216).withValues(alpha: 0.85);
      rankIndicator = const Text(
        '👑 #1',
        style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFFD700), fontSize: 13),
      );
    } else if (user.rank == 2) {
      rankBorderColor = const Color(0xFFB0BEC5).withValues(alpha: 0.5);
      rankBgColor = const Color(0xFF21282D).withValues(alpha: 0.85);
      rankIndicator = const Text(
        '🥈 #2',
        style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFCFD8DC), fontSize: 13),
      );
    } else if (user.rank == 3) {
      rankBorderColor = const Color(0xFFFF7043).withValues(alpha: 0.5);
      rankBgColor = const Color(0xFF2B1C17).withValues(alpha: 0.85);
      rankIndicator = const Text(
        '🥉 #3',
        style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFF8A65), fontSize: 13),
      );
    } else if (user.rank <= 5) {
      rankBorderColor = Colors.cyanAccent.withValues(alpha: 0.4);
      rankBgColor = const Color(0xFF102730).withValues(alpha: 0.7);
      rankIndicator = Text(
        '💎 #${user.rank}',
        style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.cyanAccent, fontSize: 12),
      );
    } else if (user.rank <= 10) {
      rankBorderColor = Colors.purpleAccent.withValues(alpha: 0.35);
      rankBgColor = const Color(0xFF25162E).withValues(alpha: 0.7);
      rankIndicator = Text(
        '🌟 #${user.rank}',
        style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.purpleAccent, fontSize: 12),
      );
    } else if (user.rank <= 20) {
      rankBorderColor = Colors.redAccent.withValues(alpha: 0.3);
      rankBgColor = const Color(0xFF2B1616).withValues(alpha: 0.6);
      rankIndicator = Text(
        '⚔️ #${user.rank}',
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 11.5),
      );
    } else if (user.rank <= 50) {
      rankBorderColor = Colors.greenAccent.withValues(alpha: 0.25);
      rankBgColor = const Color(0xFF13281A).withValues(alpha: 0.5);
      rankIndicator = Text(
        '🛡️ #${user.rank}',
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent, fontSize: 11.5),
      );
    } else {
      rankBorderColor = isMe
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
          : Colors.white.withValues(alpha: 0.05);
      rankBgColor = isMe
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
          : Theme.of(context).cardColor;
      rankIndicator = Text(
        '#${user.rank}',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.grey),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
            : rankBgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe
              ? Theme.of(context).colorScheme.primary
              : rankBorderColor,
          width: isMe || user.rank <= 3 ? 1.4 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Rank Badge with Icon
          Container(
            width: 50,
            alignment: Alignment.centerLeft,
            child: rankIndicator,
          ),
          const SizedBox(width: 4),
          // Avatar with VIP Frame
          VipAvatarFrame(
            rank: user.rank,
            radius: 18,
            child: CircleAvatar(
              radius: 18,
              backgroundImage: user.avatarUrl.isNotEmpty
                  ? CachedNetworkImageProvider(user.avatarUrl)
                  : null,
              child: user.avatarUrl.isEmpty
                  ? Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          // Name & Badges
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: isMe
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(Tôi)',
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    LevelBadge(level: user.level, fontSize: 9),
                    if (user.rank <= 50) ...[
                      const SizedBox(width: 5),
                      VipRankBadge(rank: user.rank, fontSize: 8),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Value (EXP or Chapters)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _selectedCategory == 0
                    ? '${user.exp}'
                    : '${user.claimedChaptersCount}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: user.rank == 1
                      ? const Color(0xFFFFD700)
                      : user.rank <= 5
                          ? Colors.cyanAccent
                          : Colors.amberAccent,
                ),
              ),
              Text(
                _selectedCategory == 0 ? 'EXP' : 'chương',
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMyRankBar(LeaderboardUser? myEntry) {
    final localExp = LevelService.instance.currentExp;
    final levelInfo = LevelService.getLevelInfo(localExp);
    final myRank = myEntry?.rank ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          if (myRank > 0 && myRank <= 50)
            VipRankBadge(rank: myRank, fontSize: 9.5)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                myEntry != null ? '#${myEntry.rank}' : 'Chưa xếp hạng',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Hạng của bạn',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 6),
                    LevelBadge(level: levelInfo.level, fontSize: 9.5),
                  ],
                ),
                Text(
                  _selectedCategory == 0
                      ? '$localExp EXP • ${levelInfo.title}'
                      : '~${(localExp / 10).floor()} chương đã cày',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_upward_rounded, color: Colors.greenAccent, size: 20),
        ],
      ),
    );
  }
}
