import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../config/admin_config.dart';
import '../catalog/catalog_cache_service.dart';

enum UserFilter { all, active, banned, muted, admin }

class UsersListPage extends StatefulWidget {
  const UsersListPage({super.key});

  @override
  State<UsersListPage> createState() => _UsersListPageState();
}

class _UsersListPageState extends State<UsersListPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  Timer? _debounce;
  UserFilter _currentFilter = UserFilter.all;

  final List<DocumentSnapshot> _users = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDoc;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchUsers(isRefresh: true);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _fetchUsers();
      }
    }
  }

  Future<void> _fetchUsers({bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _lastDoc = null;
        _hasMore = true;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      Query query = FirebaseFirestore.instance.collection('users').limit(30);

      if (_lastDoc != null && !isRefresh) {
        query = query.startAfterDocument(_lastDoc!);
      }

      final snapshot = await query.get();
      final docs = snapshot.docs;

      if (!mounted) return;

      setState(() {
        if (isRefresh) {
          _users.clear();
        }
        _users.addAll(docs);
        _lastDoc = docs.isNotEmpty ? docs.last : _lastDoc;
        _hasMore = docs.length >= 30;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Lọc dữ liệu theo Search và Filter trên tập users đã nạp
    final filteredDocs = _users.where((doc) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final name = (data['displayName'] ?? data['name'] ?? '').toString();
      final email = (data['email'] ?? '').toString();
      final isBanned = data['isBanned'] == true;
      final isAdmin = AdminConfig.isAdmin(data['email']?.toString());

      bool isMuted = false;
      if (data['mutedUntil'] != null) {
        try {
          final mutedUntil = (data['mutedUntil'] as Timestamp).toDate();
          if (mutedUntil.isAfter(DateTime.now())) isMuted = true;
        } catch (_) {}
      }

      // 1. Kiểm tra Search (không phân biệt dấu tiếng Việt)
      if (_searchQuery.isNotEmpty) {
        final normQuery = CatalogCacheService.instance.normalize(_searchQuery);
        final normName = CatalogCacheService.instance.normalize(name);
        final normEmail = CatalogCacheService.instance.normalize(email);
        final matches = normName.contains(normQuery) || normEmail.contains(normQuery);
        if (!matches) return false;
      }

      // 2. Kiểm tra Filter Tab
      switch (_currentFilter) {
        case UserFilter.all:
          return true;
        case UserFilter.active:
          return !isBanned && !isMuted;
        case UserFilter.banned:
          return isBanned;
        case UserFilter.muted:
          return isMuted;
        case UserFilter.admin:
          return isAdmin;
      }
    }).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Quản lý người dùng'),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 1. Thanh tìm kiếm
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(21),
                border: Border.all(
                  color: theme.dividerColor,
                ),
              ),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm theo tên hoặc email...',
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                    fontSize: 13,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.54),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            size: 16,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.54),
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                  onChanged: (val) {
                    if (_debounce?.isActive ?? false) _debounce!.cancel();
                    _debounce = Timer(const Duration(milliseconds: 150), () {
                      if (mounted) {
                        setState(() => _searchQuery = val.trim());
                      }
                    });
                  },
              ),
            ),
          ),

          // 2. Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _buildFilterChip('Tất cả', UserFilter.all),
                const SizedBox(width: 8),
                _buildFilterChip('Đang hoạt động', UserFilter.active),
                const SizedBox(width: 8),
                _buildFilterChip('Bị cấm', UserFilter.banned),
                const SizedBox(width: 8),
                _buildFilterChip('Bị cấm ngôn', UserFilter.muted),
                const SizedBox(width: 8),
                _buildFilterChip('Admin', UserFilter.admin),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 3. Danh sách người dùng
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.cloud_off_rounded,
                              size: 44,
                              color: Colors.redAccent,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Lỗi tải danh sách người dùng',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$_errorMessage\n(Đảm bảo bạn đăng nhập đúng tài khoản Admin)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () => _fetchUsers(isRefresh: true),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Thử lại'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.onSurface,
                              side: BorderSide(color: theme.dividerColor),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : filteredDocs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _searchQuery.isNotEmpty
                                  ? Icons.person_search_outlined
                                  : Icons.group_off_outlined,
                              size: 40,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'Không tìm thấy người dùng phù hợp'
                                : 'Chưa có người dùng nào trong danh mục này',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'Hãy thử tìm kiếm với tên hoặc email khác'
                                : 'Danh sách sẽ xuất hiện khi có người dùng tương ứng',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_searchQuery.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              icon: const Icon(Icons.clear, size: 16),
                              label: const Text('Xóa bộ lọc tìm kiếm'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange,
                                side: const BorderSide(color: Colors.orange),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _fetchUsers(isRefresh: true),
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: filteredDocs.length + (_isLoadingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        if (index == filteredDocs.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        final doc = filteredDocs[index];
                        final data = doc.data() as Map<String, dynamic>? ?? {};
                        return _buildUserCard(context, doc.id, data);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, UserFilter filter) {
    final isSelected = _currentFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _currentFilter = filter),
      selectedColor: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).cardColor,
      labelStyle: TextStyle(
        fontSize: 12,
        color: isSelected
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _buildUserCard(BuildContext context, String uid, Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final name = data['displayName'] ?? data['name'] ?? 'Người dùng';
    final email = data['email'] ?? 'Không có email';
    final photoUrl = (data['avatarUrl'] ?? data['avatar'] ?? data['photoURL'] ?? '').toString();
    final isValidPhotoUrl = photoUrl.startsWith('http://') || photoUrl.startsWith('https://');
    final isBanned = data['isBanned'] == true;
    final isAdmin = AdminConfig.isAdmin(data['email']?.toString());
    final groupId = data['groupId']?.toString().trim();
    final hasGroup = groupId != null && groupId.isNotEmpty;

    bool isMuted = false;
    DateTime? mutedUntil;
    if (data['mutedUntil'] != null) {
      try {
        mutedUntil = (data['mutedUntil'] as Timestamp).toDate();
        if (mutedUntil.isAfter(DateTime.now())) isMuted = true;
      } catch (_) {}
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isBanned
              ? Colors.redAccent.withValues(alpha: 0.5)
              : isMuted
              ? Colors.orangeAccent.withValues(alpha: 0.4)
              : theme.dividerColor,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          backgroundImage: isValidPhotoUrl ? CachedNetworkImageProvider(photoUrl) : null,
          child: !isValidPhotoUrl
              ? Icon(Icons.person, color: theme.colorScheme.onSurface.withValues(alpha: 0.54), size: 20)
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isBanned ? Colors.redAccent : theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (isAdmin)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'ADMIN',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
            if (isBanned)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'BỊ CẤM',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              )
            else if (isMuted)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'CẤM NGÔN',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            if (hasGroup)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'NHÓM DỊCH',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onPrimary),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12),
            ),
            if (isMuted && mutedUntil != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Cấm ngôn đến: ${mutedUntil.hour}:${mutedUntil.minute.toString().padLeft(2, '0')} ${mutedUntil.day}/${mutedUntil.month}',
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
                ),
              ),
          ],
        ),
        trailing: Icon(Icons.more_vert, color: theme.colorScheme.onSurface.withValues(alpha: 0.54)),
        onTap: () => _showUserActionSheet(context, uid, data, isBanned, isMuted, mutedUntil),
      ),
    );
  }

  void _showUserActionSheet(
    BuildContext context,
    String uid,
    Map<String, dynamic> data,
    bool isBanned,
    bool isMuted,
    DateTime? mutedUntil,
  ) {
    final name = data['displayName'] ?? data['name'] ?? 'Người dùng';
    final email = data['email'] ?? 'Không có email';
    final bio = data['bio'] ?? '';
    final createdAt = data['createdAt'] is Timestamp
        ? (data['createdAt'] as Timestamp).toDate()
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Header Sheet
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            email,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: theme.colorScheme.onSurface.withValues(alpha: 0.54)),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Thông tin chi tiết
                if (bio.toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'Tiểu sử: $bio',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                Text(
                  'UID: $uid',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    fontSize: 11,
                  ),
                ),
                if (createdAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 8),
                    child: Text(
                      'Ngày tạo: ${timeago.format(createdAt, locale: 'vi')}',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                  ),

                const Divider(height: 16),

                // 1. Sao chép UID
                ListTile(
                  leading: Icon(Icons.copy_rounded, color: Theme.of(context).colorScheme.primary),
                  title: const Text('Sao chép UID'),
                  dense: true,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Clipboard.setData(ClipboardData(text: uid));
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã sao chép UID người dùng'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),

                // Sao chép Email
                if (email.isNotEmpty && email != 'Không có email')
                  ListTile(
                    leading: const Icon(Icons.email_outlined, color: Colors.indigoAccent),
                    title: const Text('Sao chép Email'),
                    dense: true,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Clipboard.setData(ClipboardData(text: email));
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Đã sao chép Email người dùng'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),

                // 2. Chỉnh sửa tên hiển thị / Bio
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded, color: Colors.cyanAccent),
                  title: const Text('Chỉnh sửa thông tin hồ sơ'),
                  dense: true,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showEditUserDialog(context, uid, name, bio.toString());
                  },
                ),

                // 3. Cấm ngôn / Gỡ cấm ngôn
                if (isMuted)
                  ListTile(
                    leading: const Icon(Icons.volume_up, color: Colors.greenAccent),
                    title: const Text('Gỡ cấm ngôn'),
                    dense: true,
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      try {
                        await FirebaseFirestore.instance.collection('users').doc(uid).update({
                          'mutedUntil': FieldValue.delete(),
                          'mutedReason': FieldValue.delete(),
                        });
                        _fetchUsers(isRefresh: true);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Đã gỡ cấm ngôn $name'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.timer_off_outlined, color: Colors.orangeAccent),
                    title: const Text('Cấm ngôn (Tạm khóa chat & bình luận)'),
                    dense: true,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showMuteUserDialog(context, uid, name);
                    },
                  ),

                // 4. Cấm / Gỡ cấm tài khoản
                ListTile(
                  leading: Icon(
                    isBanned ? Icons.lock_open : Icons.block,
                    color: isBanned ? Colors.greenAccent : Colors.redAccent,
                  ),
                  title: Text(
                    isBanned ? 'Gỡ cấm tài khoản' : 'Cấm tài khoản (Ban toàn bộ)',
                    style: TextStyle(
                      color: isBanned ? Colors.greenAccent : Colors.redAccent,
                    ),
                  ),
                  dense: true,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: Text(
                          isBanned ? 'Gỡ cấm tài khoản?' : 'Cấm tài khoản?',
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        content: Text(
                          isBanned
                              ? 'Bạn có chắc muốn gỡ cấm cho người dùng "$name" không?'
                              : 'Người dùng "$name" sẽ bị chặn toàn bộ quyền đăng bài, bình luận và chat.',
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isBanned ? Colors.green : Colors.redAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(isBanned ? 'Gỡ cấm' : 'Xác nhận cấm', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      try {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .update({'isBanned': !isBanned});
                        _fetchUsers(isRefresh: true);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isBanned ? 'Đã gỡ cấm $name' : 'Đã cấm tài khoản $name'),
                              backgroundColor: isBanned ? Colors.green : Colors.redAccent,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    }
                  },
                ),

                // 5. Xóa tài khoản khỏi Firestore
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Xóa hồ sơ khỏi hệ thống', style: TextStyle(color: Colors.red)),
                  dense: true,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: Text(
                          'Xóa người dùng?',
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        content: Text(
                          'Bạn có chắc chắn muốn xóa hồ sơ của "$name" khỏi Firestore không? Hành động này không thể hoàn tác.',
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Xóa vĩnh viễn', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      try {
                        await FirebaseFirestore.instance.collection('users').doc(uid).delete();
                        _fetchUsers(isRefresh: true);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Đã xóa hồ sơ người dùng $name'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditUserDialog(BuildContext context, String uid, String currentName, String currentBio) {
    showDialog(
      context: context,
      builder: (ctx) => _EditUserDialog(
        uid: uid,
        currentName: currentName,
        currentBio: currentBio,
        onSaved: () => _fetchUsers(isRefresh: true),
      ),
    );
  }


  void _showMuteUserDialog(BuildContext context, String uid, String name) {
    final options = [
      {'label': '10 phút', 'duration': const Duration(minutes: 10)},
      {'label': '1 giờ', 'duration': const Duration(hours: 1)},
      {'label': '24 giờ', 'duration': const Duration(hours: 24)},
      {'label': '7 ngày', 'duration': const Duration(days: 7)},
      {'label': '30 ngày', 'duration': const Duration(days: 30)},
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Cấm ngôn $name',
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((opt) {
            final label = opt['label'] as String;
            final duration = opt['duration'] as Duration;
            return ListTile(
              title: Text(label, style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface)),
              trailing: const Icon(Icons.timer_outlined, size: 18),
              onTap: () async {
                try {
                  final mutedUntil = DateTime.now().add(duration);
                  await FirebaseFirestore.instance.collection('users').doc(uid).update({
                    'mutedUntil': Timestamp.fromDate(mutedUntil),
                    'mutedReason': 'Vi phạm quy định diễn đàn',
                  });
                  _fetchUsers(isRefresh: true);
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Đã cấm ngôn $name trong $label'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}

class _EditUserDialog extends StatefulWidget {
  final String uid;
  final String currentName;
  final String currentBio;
  final VoidCallback onSaved;

  const _EditUserDialog({
    required this.uid,
    required this.currentName,
    required this.currentBio,
    required this.onSaved,
  });

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.currentName);
    _bioCtrl = TextEditingController(text: widget.currentBio);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newName = _nameCtrl.text.trim();
    final newBio = _bioCtrl.text.trim();
    if (newName.isEmpty) return;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.uid).update({
        'name': newName,
        'displayName': newName,
        'bio': newBio,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      widget.onSaved();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật thông tin người dùng'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).dialogTheme.backgroundColor ?? Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Chỉnh sửa thông tin',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            decoration: const InputDecoration(
              labelText: 'Tên hiển thị',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bioCtrl,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            decoration: const InputDecoration(
              labelText: 'Tiểu sử (Bio)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Lưu', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
