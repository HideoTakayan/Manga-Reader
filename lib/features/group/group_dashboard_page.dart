import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models_group.dart';
import '../../data/models_cloud.dart';
import '../../data/drive_service.dart';
import '../../services/group_service.dart';
import 'group_manga_manager_page.dart';

class GroupDashboardPage extends StatefulWidget {
  const GroupDashboardPage({super.key});

  @override
  State<GroupDashboardPage> createState() => _GroupDashboardPageState();
}

class _GroupDashboardPageState extends State<GroupDashboardPage> {
  dynamic _driveAccount;
  List<CloudManga> _groupMangas = [];
  bool _isLoadingMangas = true;

  @override
  void initState() {
    super.initState();
    _driveAccount = DriveService.instance.currentUser;
    DriveService.instance.onAuthStateChanged.listen((account) {
      if (mounted) setState(() => _driveAccount = account);
    });
    _loadGroupStats();
  }

  Future<void> _loadGroupStats() async {
    final allMangas = await DriveService.instance.getMangas();
    if (mounted) {
      setState(() {
        _groupMangas = allMangas;
        _isLoadingMangas = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: StreamBuilder<ScanlationGroup?>(
        stream: GroupService.instance.currentGroupStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'Lỗi tải nhóm: ${snapshot.error}',
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            );
          }

          final group = snapshot.data;
          if (group == null) {
            return _buildNoGroupState(context);
          }

          final currentUser = FirebaseAuth.instance.currentUser;
          final isLeader = currentUser?.uid == group.leaderId;
          final groupMangaList = _groupMangas.where((m) => m.uploaderGroupId == group.id).toList();
          final totalViews = groupMangaList.fold<int>(0, (total, m) => total + m.viewCount);
          final totalLikes = groupMangaList.fold<int>(0, (total, m) => total + m.likeCount);

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // 1. Premium Header with Avatar & Stats Ribbon
              _buildSliverHeader(context, group, isLeader, groupMangaList.length, totalViews, totalLikes),

              // 2. Main Dashboard Content
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // 1. Quản lý Truyện của Nhóm (Sleek Action Card)
                    _buildMainActionBanner(context, group, groupMangaList.length),
                    const SizedBox(height: 14),

                    // 2. Google Drive Status Pill
                    _buildDriveStatusCard(context, group),
                    const SizedBox(height: 14),

                    // 3. Invite Code Card (Leader Only - Fixed Overflow & Clean Monospace)
                    if (isLeader) ...[
                      _buildInviteCodeCard(context, group),
                      const SizedBox(height: 18),
                    ],

                    // 4. Manga Preview Section
                    _buildMangaPreviewSection(context, group, groupMangaList),
                    const SizedBox(height: 22),

                    // 5. Members List
                    _buildMembersSection(context, group, currentUser?.uid, isLeader),
                    const SizedBox(height: 24),

                    // 6. Leave Group Action
                    if (!isLeader)
                      _buildLeaveGroupButton(context, group),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── 1. SLIVER APP BAR & STATS ────────────────────────────────────────────

  Widget _buildSliverHeader(
    BuildContext context,
    ScanlationGroup group,
    bool isLeader,
    int mangaCount,
    int totalViews,
    int totalLikes,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SliverAppBar(
      expandedHeight: 225.0,
      pinned: true,
      stretch: true,
      elevation: 0,
      backgroundColor: theme.scaffoldBackgroundColor,
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground, StretchMode.blurBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Soft Ambient Background
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.cardColor,
                    theme.scaffoldBackgroundColor,
                  ],
                ),
              ),
            ),

            // Soft radial glow (Blue / Violet)
            Positioned(
              top: -30,
              right: -20,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blueAccent.withValues(alpha: isDark ? 0.15 : 0.08),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),

            // Header Content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Group Profile Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Avatar Container with sleek border
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.cardColor,
                            border: Border.all(
                              color: Colors.blueAccent.withValues(alpha: 0.6),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blueAccent.withValues(alpha: 0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.groups_rounded, color: Colors.blueAccent, size: 30),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      group.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.3,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.verified_rounded, size: 11, color: Color(0xFF60A5FA)),
                                        SizedBox(width: 3),
                                        Text(
                                          'OFFICIAL',
                                          style: TextStyle(
                                            color: Color(0xFF60A5FA),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                group.description.isNotEmpty ? group.description : 'Nhóm dịch Manga & Novel',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 12.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Modern 4-metric Ribbon
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      decoration: BoxDecoration(
                        color: theme.cardColor.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(child: _buildMetricItem('Truyện', _isLoadingMangas ? '...' : '$mangaCount', Icons.auto_stories_rounded, Colors.blueAccent)),
                          _buildVerticalDivider(),
                          Expanded(child: _buildMetricItem('Thành viên', '${group.members.length}', Icons.people_alt_rounded, Colors.tealAccent)),
                          _buildVerticalDivider(),
                          Expanded(child: _buildMetricItem('Lượt xem', _formatNumber(totalViews), Icons.remove_red_eye_rounded, Colors.amberAccent)),
                          _buildVerticalDivider(),
                          Expanded(child: _buildMetricItem('Lượt thích', _formatNumber(totalLikes), Icons.favorite_rounded, Colors.pinkAccent)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem(String label, String value, IconData icon, Color accentColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: accentColor),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
        ),
      ],
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      width: 1,
      height: 22,
      color: Colors.white.withValues(alpha: 0.08),
    );
  }

  // ── 2. MAIN ACTION CARD (QUẢN LÝ TRUYỆN) ─────────────────────────────────

  Widget _buildMainActionBanner(BuildContext context, ScanlationGroup group, int mangaCount) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => GroupMangaManagerPage(group: group)),
            ).then((_) => _loadGroupStats());
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                // Icon Box with gradient accent
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.library_books_rounded, color: Colors.blueAccent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quản lý Truyện của Nhóm',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Đăng truyện mới, quản lý chapter, sửa metadata',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white70,
                    size: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 3. GOOGLE DRIVE STATUS CARD ──────────────────────────────────────────

  Widget _buildDriveStatusCard(BuildContext context, ScanlationGroup group) {
    final theme = Theme.of(context);
    final isConnected = _driveAccount != null;
    final email = isConnected ? _driveAccount!.email : null;

    final statusColor = isConnected ? const Color(0xFF10B981) : const Color(0xFFF43F5E);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.25),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      isConnected ? 'Google Drive: Đã kết nối' : 'Google Drive: Chưa kết nối',
                      style: TextStyle(
                        color: isConnected ? const Color(0xFF34D399) : const Color(0xFFFB7185),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.6),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  isConnected ? '$email' : 'Cần kết nối Drive để đăng truyện & chapter',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: isConnected ? Colors.white70 : Colors.blueAccent,
              side: BorderSide(
                color: isConnected ? Colors.white24 : Colors.blueAccent.withValues(alpha: 0.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => _handleDriveToggle(group),
            child: Text(
              isConnected ? 'Ngắt' : 'Kết nối',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDriveToggle(ScanlationGroup group) async {
    final isConnected = _driveAccount != null;
    if (!isConnected) {
      try {
        await DriveService.instance.signIn();
      } catch (e) {
        if (!mounted) return;
        final errStr = e.toString().toLowerCase();
        if (!errStr.contains('huỷ') && !errStr.contains('cancel')) {
          _showDriveRequestDialog(group);
        }
      }
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
          title: const Text('Ngắt kết nối Drive?', style: TextStyle(color: Colors.white)),
          content: Text(
            'Tài khoản hiện tại: ${_driveAccount!.email}',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ngắt kết nối', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
      if (confirm == true) await DriveService.instance.signOut();
    }
  }

  void _showDriveRequestDialog(ScanlationGroup group) {
    final user = FirebaseAuth.instance.currentUser;
    final emailController = TextEditingController(text: user?.email ?? '');
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Yêu cầu quyền truy cập Drive', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tài khoản Google của bạn chưa được Admin thêm vào Test Users.\nNhập email bên dưới để gửi yêu cầu cho Admin cấp quyền:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: emailController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Email Google',
                labelStyle: const TextStyle(color: Colors.blueAccent),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await FirebaseFirestore.instance.collection('drive_access_requests').doc(user?.uid ?? email).set({
                  'email': email,
                  'uid': user?.uid ?? '',
                  'displayName': user?.displayName ?? '',
                  'groupId': group.id,
                  'groupName': group.name,
                  'status': 'pending',
                  'createdAt': FieldValue.serverTimestamp(),
                });
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Đã gửi yêu cầu cho Admin! Vui lòng chờ Admin phê duyệt.'),
                      duration: Duration(seconds: 4),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                }
              }
            },
            child: const Text('Gửi yêu cầu', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── 4. LEADER INVITE CODE (FIXED OVERFLOW & CLEAN STYLING) ────────────────

  Widget _buildInviteCodeCard(BuildContext context, ScanlationGroup group) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with clean Wrap/Row to prevent overflow on small screens
          Row(
            children: [
              const Icon(Icons.vpn_key_rounded, color: Color(0xFFFBBF24), size: 16),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'MÃ MỜI THÀNH VIÊN',
                  style: TextStyle(
                    color: Color(0xFFFBBF24),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'TRƯỞNG NHÓM',
                  style: TextStyle(
                    color: Color(0xFFFBBF24),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Code Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    group.inviteCode,
                    style: const TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Sao chép mã',
                  icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    Clipboard.setData(ClipboardData(text: group.inviteCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Đã sao chép mã mời: ${group.inviteCode}')),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Tạo mã mới',
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white54, size: 18),
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: EdgeInsets.zero,
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    await GroupService.instance.refreshInviteCode(group.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Đã làm mới mã mời thành công!')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Thành viên nhập mã này trong Cài đặt → Tham gia nhóm dịch.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ── 5. MANGA PREVIEW SECTION ─────────────────────────────────────────────

  Widget _buildMangaPreviewSection(BuildContext context, ScanlationGroup group, List<CloudManga> mangas) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Truyện của Nhóm',
              style: TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800),
            ),
            if (mangas.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => GroupMangaManagerPage(group: group)),
                  ).then((_) => _loadGroupStats());
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                icon: const Icon(Icons.chevron_right_rounded, color: Colors.blueAccent, size: 16),
                label: const Text(
                  'Xem tất cả',
                  style: TextStyle(color: Colors.blueAccent, fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (mangas.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.library_add_rounded, size: 36, color: Colors.white.withValues(alpha: 0.25)),
                  const SizedBox(height: 8),
                  Text(
                    'Nhóm chưa đăng bộ truyện nào',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blueAccent,
                      side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      minimumSize: const Size(0, 32),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Đăng bộ truyện đầu tiên', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => GroupMangaManagerPage(group: group)),
                      ).then((_) => _loadGroupStats());
                    },
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: mangas.length > 5 ? 5 : mangas.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final manga = mangas[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => GroupMangaManagerPage(group: group)),
                    );
                  },
                  child: Container(
                    width: 115,
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildMangaCover(manga.coverFileId),
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                              stops: [0.55, 1.0],
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 6,
                          left: 6,
                          right: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                manga.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(Icons.remove_red_eye_rounded, size: 10, color: Colors.white60),
                                  const SizedBox(width: 3),
                                  Text(
                                    _formatNumber(manga.viewCount),
                                    style: const TextStyle(color: Colors.white60, fontSize: 9.5),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildMangaCover(String fileId) {
    if (fileId.isEmpty) {
      return Container(
        color: const Color(0xFF1E2028),
        child: const Icon(Icons.book_rounded, color: Colors.white24),
      );
    }
    return Image.network(
      DriveService.instance.mediaUrl(fileId),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: const Color(0xFF1E2028),
        child: const Icon(Icons.broken_image_rounded, color: Colors.white24),
      ),
    );
  }

  // ── 6. MEMBERS SECTION ───────────────────────────────────────────────────

  Widget _buildMembersSection(BuildContext context, ScanlationGroup group, String? currentUid, bool isLeader) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Thành viên trong nhóm',
              style: TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${group.members.length}',
                style: const TextStyle(color: Colors.blueAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: group.members.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final memberId = group.members[index];
            final isMemberLeader = memberId == group.leaderId;
            final isSelf = memberId == currentUid;

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(memberId).get(),
              builder: (context, userSnapshot) {
                String displayName = 'Đang tải...';
                String? avatarUrl;

                if (userSnapshot.hasData && userSnapshot.data!.exists) {
                  final data = userSnapshot.data!.data() as Map<String, dynamic>?;
                  if (data != null) {
                    displayName = data['displayName'] ?? data['name'] ?? 'Thành viên';
                    avatarUrl = data['photoURL'] ?? data['avatarUrl'] ?? data['avatar'];
                  }
                }

                return Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isMemberLeader
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white10,
                          backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
                          child: (avatarUrl == null || avatarUrl.isEmpty)
                              ? const Icon(Icons.person_rounded, color: Colors.white54, size: 18)
                              : null,
                        ),
                        if (isMemberLeader)
                          Positioned(
                            bottom: -1,
                            right: -1,
                            child: Container(
                              padding: const EdgeInsets.all(1.5),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFF59E0B),
                              ),
                              child: const Icon(Icons.star_rounded, size: 8, color: Colors.black),
                            ),
                          ),
                      ],
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSelf) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('BẠN', style: TextStyle(color: Colors.blueAccent, fontSize: 8.5, fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      isMemberLeader ? 'Trưởng nhóm' : 'Thành viên',
                      style: TextStyle(
                        color: isMemberLeader ? const Color(0xFFFBBF24) : Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                        fontWeight: isMemberLeader ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    trailing: (isLeader && !isMemberLeader)
                        ? IconButton(
                            icon: const Icon(Icons.person_remove_rounded, color: Colors.redAccent, size: 18),
                            tooltip: 'Xóa khỏi nhóm',
                            onPressed: () => _confirmRemoveMember(context, group, memberId, displayName),
                          )
                        : null,
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  void _confirmRemoveMember(BuildContext context, ScanlationGroup group, String memberId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        title: const Text('Xác nhận', style: TextStyle(color: Colors.white)),
        content: Text('Bạn có chắc chắn muốn xóa "$name" khỏi nhóm dịch không?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await GroupService.instance.removeMember(group.id, memberId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã xóa $name khỏi nhóm')),
                );
              }
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── 7. LEAVE GROUP BUTTON ────────────────────────────────────────────────

  Widget _buildLeaveGroupButton(BuildContext context, ScanlationGroup group) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFF43F5E),
        side: BorderSide(color: const Color(0xFFF43F5E).withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.exit_to_app_rounded, size: 16),
      label: const Text('Rời khỏi Nhóm dịch', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      onPressed: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
            title: const Text('Xác nhận rời nhóm?', style: TextStyle(color: Colors.white)),
            content: Text('Bạn sẽ không còn là thành viên của "${group.name}".', style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Rời nhóm', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await GroupService.instance.leaveGroup(group.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã rời nhóm thành công')),
            );
          }
        }
      },
    );
  }

  // ── 8. NO GROUP STATE ────────────────────────────────────────────────────

  Widget _buildNoGroupState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.groups_outlined, size: 40, color: Colors.blueAccent),
            ),
            const SizedBox(height: 18),
            const Text(
              'Chưa tham gia Nhóm dịch',
              style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Bạn chưa tham gia hoặc nhóm dịch của bạn đang chờ Admin phê duyệt.\n\nVào Cài đặt → Tạo nhóm hoặc Nhập mã mời để tham gia!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}
