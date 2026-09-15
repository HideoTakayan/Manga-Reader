import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../catalog/catalog_cache_service.dart';

// Trang trợ giúp với FAQs, Hướng dẫn, và thông tin Liên hệ.
// Toàn bộ nội dung được hardcode — không cần API hay database.

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  final List<Map<String, String>> _faqs = [
    {
      'question': 'App hỗ trợ những định dạng truyện nào?',
      'answer':
          'MangaReader hỗ trợ đa dạng các định dạng phong phú:\n'
          '- Truyện tranh: CBZ, ZIP, CBT, TAR, PDF tối ưu hoá cực mượt.\n'
          '- Tiểu thuyết/Ebook: EPUB (Đọc chương, tìm kiếm, tùy chỉnh font/nền, đọc giọng nói TTS).\n'
          '- Định dạng hình ảnh: JPG, PNG, WEBP, AVIF, HEIC, JFIF, BMP, GIF.\n'
          '- Nhập truyện từ máy: Hỗ trợ quét tự động thư mục MangaReader hoặc chọn file ngoài.',
    },
    {
      'question': 'Làm sao để thao tác khi đọc truyện & tiểu thuyết?',
      'answer':
          '1. Truyện tranh (CBZ/ZIP/CBT/TAR/PDF): Chạm cạnh trái/phải hoặc vuốt để lật trang; chạm 30% giữa màn hình để bật thanh công cụ.\n'
          '2. Tiểu thuyết (EPUB): Hỗ trợ đọc cuộn dọc hoặc lật trang, tìm kiếm nội dung thông minh, điều chỉnh cỡ chữ, font chữ, màu nền và Nghe đọc tự động (TTS tiếng Việt).\n'
          '3. Phím cứng & Bàn phím / Page Turner:\n'
          '   • Phím Tăng/Giảm âm lượng hoặc Mũi tên / Space / PageUp / PageDown để lật trang.\n'
          '   • Phím M (Menu), B (Bookmark), A (Tự cuộn), F (Theo dõi), T (Bật/tắt TTS), [/] (Chuyển chương), +/- (Cỡ chữ).',
    },
    {
      'question': 'Diễn đàn (Forum) dùng để làm gì?',
      'answer':
          'Diễn đàn là nơi cộng đồng giao lưu, chia thành 3 khu vực:\n'
          '- Diễn đàn: Nhắn tin trực tuyến (Real-time) cùng mọi người.\n'
          '- Chia sẻ truyện: Đăng bài giới thiệu truyện hay.\n'
          '- Thảo luận: Nơi bàn luận các chủ đề nóng hổi.\n'
          'Bạn có thể Đăng bài, Bình luận, Thả tim (Like) và gửi Ảnh/GIF.',
    },
    {
      'question': 'Làm sao để lưu lại trang đang đọc?',
      'answer':
          'App tự động lưu lại Tiến trình đọc của bạn một cách chính xác trên từng trang.\n\n'
          'Ngoài ra, bạn có thể chạm vào giữa màn hình, bấm icon Bookmark (Lưu trang) ở góc trên để đánh dấu lại vị trí ưa thích. Bấm vào bookmark sẽ nhảy ngay đến trang đã lưu.',
    },
    {
      'question': 'Làm sao để theo dõi & nhận thông báo?',
      'answer':
          '- Theo dõi: Click icon ❤️ ở trang chi tiết, truyện sẽ vào thư viện "Theo dõi".\n'
          '- Thông báo: Click icon 🔔 để nhận cảnh báo khi có Chapter mới.\n\n'
          'Lưu ý: Bạn cần đăng nhập để sử dụng tính năng này.',
    },
    {
      'question': 'Quản lý dung lượng và tải xuống như thế nào?',
      'answer':
          'Bạn có thể vào Cài đặt → Quản lý Dung lượng để theo dõi dung lượng bộ nhớ đã tải, xóa cache giải nén hoặc xóa các chương đã đọc để tiết kiệm dung lượng điện thoại.',
    },
    {
      'question': 'Làm sao để đăng nhập bằng Google?',
      'answer':
          'Ở trang đăng nhập:\n'
          '1. Click nút "Đăng nhập bằng Google"\n'
          '2. Chọn tài khoản Google của bạn\n'
          '3. Đăng nhập thành công!\n\n'
          'Bạn có thể thêm mật khẩu sau ở Settings → Thêm mật khẩu.',
    },
  ];

  // Guide data: mỗi item có 'content' dài — chỉ hiện khi tap (dialog)
  final List<Map<String, String>> _guides = [
    {
      'title': 'Đăng ký tài khoản',
      'description': 'Hướng dẫn tạo tài khoản mới và đăng nhập',
      'content':
          '📝 ĐĂNG KÝ TÀI KHOẢN\n\n'
          '1️⃣ Mở app MangaReader\n'
          '2️⃣ Tại màn hình đăng nhập, click "Chưa có tài khoản? Đăng ký ngay"\n'
          '3️⃣ Nhập thông tin (Email, Mật khẩu)\n'
          '4️⃣ Click nút "Đăng ký"\n'
          '5️⃣ Nhận link xác thực trong Email và tiến hành Đăng nhập\n\n'
          '🔐 ĐĂNG NHẬP BẰNG GOOGLE\n\n'
          '1️⃣ Tại màn hình đăng nhập, click "Đăng nhập bằng Google"\n'
          '2️⃣ Chọn tài khoản Google\n'
          '3️⃣ Vào Settings để thiết lập thêm Mật khẩu (nếu cần)',
    },
    {
      'title': 'Khám phá tính năng Đọc Truyện',
      'description': 'Hỗ trợ PDF, EPUB, CBZ, ZIP, CBT, TAR & Phím tắt',
      'content':
          '📖 ĐỌC TRUYỆN ĐA ĐỊNH DẠNG\n\n'
          '1️⃣ TRUYỆN TRANH (ZIP, CBZ, CBT, TAR, PDF)\n'
          '   • Vuốt trái/phải hoặc cuộn dọc mượt mà\n'
          '   • Dùng phím Âm lượng hoặc Bàn phím để chuyển trang\n'
          '   • Double tap để phóng to nhanh\n\n'
          '2️⃣ TIỂU THUYẾT (EPUB, NOVEL)\n'
          '   • Chạm giữa màn hình để mở Bảng điều khiển\n'
          '   • Tuỳ chỉnh Font chữ, Cỡ chữ, Khoảng cách dòng\n'
          '   • Thay đổi Màu nền (Trắng/Tối/Sepia/Mắt/AMOLED)\n'
          '   • Trình đọc AI (TTS) tiếng Việt tự động đọc từng đoạn\n\n'
          '3️⃣ PHÍM TẮT & BLUETOOTH PAGE TURNER\n'
          '   • Mũi tên / Space / PageUp / PageDown: Lật trang / cuộn mượt\n'
          '   • Phím M: Mở thanh điều khiển\n'
          '   • Phím B: Đánh dấu trang (Bookmark)\n'
          '   • Phím A: Bật/tắt tự cuộn\n'
          '   • Phím T: Bật/tắt giọng đọc TTS\n'
          '   • Phím +/-: Tăng/giảm cỡ chữ EPUB\n'
          '   • Phím [/]: Chuyển chương trước/sau\n\n'
          '4️⃣ ĐIỀU HƯỚNG & BOOKMARK\n'
          '   • Thanh Slider dưới đáy: Kéo nhanh đến trang mong muốn\n'
          '   • Nút Bookmark: Lưu lại vị trí trang hay\n'
          '   • Tiến trình đọc luôn được lưu tự động!',
    },
    {
      'title': 'Giao lưu tại Diễn đàn',
      'description': 'Diễn đàn, Đăng bài, Bình luận & Thả tim',
      'content':
          '🌐 THAM GIA DIỄN ĐÀN\n\n'
          '1️⃣ DIỄN ĐÀN (GLOBAL CHAT)\n'
          '   • Nơi chém gió, giao lưu trực tuyến với toàn server\n'
          '   • Hỗ trợ gửi text, emoji, và cả hình động (GIF)\n\n'
          '2️⃣ CHIA SẺ & THẢO LUẬN\n'
          '   • Đăng bài viết chia sẻ truyện hay hoặc lập Topic thảo luận\n'
          '   • Có thể đính kèm Ảnh / GIF vào bài đăng\n'
          '   • Tương tác với người khác: Thả tim (Like), Bình luận (Comment)\n\n'
          '3️⃣ QUẢN LÝ BÀI VIẾT\n'
          '   • Bạn có thể Xóa bài viết / Xóa bình luận của chính mình\n'
          '   • Báo cáo (Report) nếu thấy bài viết vi phạm\n'
          '   • Admin sẽ có quyền kiểm duyệt mọi bài đăng!',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final query = CatalogCacheService.instance.normalize(_searchQuery);

    final filteredFAQs = _faqs.where((faq) {
      if (query.isEmpty) return true;
      final qNorm = CatalogCacheService.instance.normalize(faq['question'] ?? '');
      final aNorm = CatalogCacheService.instance.normalize(faq['answer'] ?? '');
      return qNorm.contains(query) || aNorm.contains(query);
    }).toList();

    final filteredGuides = _guides.where((guide) {
      if (query.isEmpty) return true;
      final titleNorm = CatalogCacheService.instance.normalize(guide['title'] ?? '');
      final descNorm = CatalogCacheService.instance.normalize(guide['description'] ?? '');
      final contentNorm = CatalogCacheService.instance.normalize(guide['content'] ?? '');
      return titleNorm.contains(query) || descNorm.contains(query) || contentNorm.contains(query);
    }).toList();

    final hasResults = filteredFAQs.isNotEmpty || filteredGuides.isNotEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Trợ giúp', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.85),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSearchBar(),
          const SizedBox(height: 20),

          if (_searchQuery.isNotEmpty && !hasResults)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.search_off_rounded,
                        size: 42,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Không tìm thấy kết quả phù hợp',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Thử tìm kiếm với từ khóa khác như "tải xuống", "đăng nhập", "TTS"...',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

          if (filteredFAQs.isNotEmpty) ...[
            _buildSectionHeader('❓ Câu hỏi thường gặp'),
            const SizedBox(height: 8),
            ...filteredFAQs.map((faq) => _buildFAQItem(faq)),
            const SizedBox(height: 24),
          ],

          if (filteredGuides.isNotEmpty) ...[
            _buildSectionHeader('📖 Hướng dẫn sử dụng'),
            const SizedBox(height: 8),
            ...filteredGuides.map((guide) => _buildGuideItem(guide)),
            const SizedBox(height: 24),
          ],

          if (_searchQuery.isEmpty) ...[
            _buildSectionHeader('📧 Liên hệ hỗ trợ'),
            const SizedBox(height: 8),
            _buildContactInfo(),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      style: const TextStyle(color: Colors.white),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Tìm câu hỏi, hướng dẫn, định dạng...',
        hintStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: Theme.of(context).cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        prefixIcon: const Icon(Icons.search, color: Colors.grey),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
      ),
      onChanged: (value) {
        if (_debounce?.isActive ?? false) _debounce!.cancel();
        _debounce = Timer(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _searchQuery = value);
        });
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildFAQItem(Map<String, String> faq) {
    return Card(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ExpansionTile(
        shape: const Border(), // Remove default borders on expansion
        title: Text(
          faq['question']!,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        iconColor: Colors.orange, // Icon khi expand
        collapsedIconColor: Colors.grey, // Icon khi collapse
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              faq['answer']!,
              style: const TextStyle(color: Colors.grey, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideItem(Map<String, String> guide) {
    return Card(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.book, color: Colors.orange),
        ),
        title: Text(
          guide['title']!,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        subtitle: Text(
          guide['description']!,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => _showGuideDialog(guide),
      ),
    );
  }

  void _showGuideDialog(Map<String, String> guide) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ?? Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.book, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                guide['title']!,
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            guide['content'] ??
                guide['description']!, // fallback nếu không có 'content'
            style: TextStyle(
              color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.6,
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildContactInfo() {
    return Card(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.email, color: Colors.orange),
            ),
            title: Text(
              'Email',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            subtitle: const Text(
              'minhhieued245@gmail.com',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            trailing: const Icon(Icons.send, color: Colors.grey),
            onTap: () async {
              // Uri scheme 'mailto' → mở email app tự động điền địa chỉ + subject
              final Uri emailUri = Uri(
                scheme: 'mailto',
                path: 'minhhieued245@gmail.com',
                query: 'subject=Hỗ trợ MangaReader',
              );
              if (await canLaunchUrl(emailUri)) {
                await launchUrl(emailUri);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Không thể mở email'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
          Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.facebook, color: Colors.blueAccent),
            ),
            title: Text(
              'Facebook',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            subtitle: const Text(
              'Nhắn tin qua Facebook',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            trailing: const Icon(Icons.open_in_new, color: Colors.grey),
            onTap: () async {
              final Uri fbUri = Uri.parse(
                'https://www.facebook.com/minh.hieu.126210/?locale=vi_VN',
              );
              // LaunchMode.externalApplication: mở trong browser/app bên ngoài, không in-app WebView
              if (await canLaunchUrl(fbUri)) {
                await launchUrl(fbUri, mode: LaunchMode.externalApplication);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Không thể mở Facebook'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
