import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// Trang trợ giúp với FAQs, Hướng dẫn, và thông tin Liên hệ.
// Toàn bộ nội dung được hardcode — không cần API hay database.

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  String _searchQuery = '';

  final List<Map<String, String>> _faqs = [
    {
      'question': 'App hỗ trợ những định dạng truyện nào?',
      'answer':
          'MangaReader hỗ trợ đa dạng các định dạng:\n'
          '- PDF: Tối ưu hoá cực mượt cho cả file khổng lồ (>50MB).\n'
          '- Truyện tranh: ZIP, CBZ.\n'
          '- Tiểu thuyết/Light Novel: TXT.\n'
          '- Sách điện tử: EPUB.',
    },
    {
      'question': 'Làm sao để thao tác khi đọc truyện?',
      'answer':
          '1. Truyện tranh/EPUB: Swipe (vuốt) sang trái/phải để lật trang.\n'
          '2. PDF: Vuốt dọc để cuộn trang, dùng 2 ngón tay (Pinch) để phóng to/thu nhỏ.\n'
          '3. Tiểu thuyết (TXT): Vuốt dọc để cuộn, chạm giữa màn hình để đổi Font chữ, Kích thước hoặc Màu nền.\n'
          '4. Phím cứng: Dùng phím Tăng/Giảm âm lượng để lật trang (Trừ PDF).',
    },
    {
      'question': 'Diễn đàn (Forum) dùng để làm gì?',
      'answer':
          'Diễn đàn là nơi cộng đồng giao lưu, chia thành 3 khu vực:\n'
          '- Chat tổng: Nhắn tin trực tuyến (Real-time) cùng mọi người.\n'
          '- Chia sẻ truyện: Đăng bài giới thiệu truyện hay.\n'
          '- Thảo luận: Nơi bàn luận các chủ đề nóng hổi.\n'
          'Bạn có thể Đăng bài, Bình luận, Thả tim (Like) và gửi Ảnh/GIF.',
    },
    {
      'question': 'Làm sao để lưu lại trang đang đọc?',
      'answer':
          'App tự động lưu lại Tiến trình đọc của bạn một cách chính xác.\n\n'
          'Ngoài ra, bạn có thể chạm vào giữa màn hình, bấm icon Bookmark (Lưu trang) ở góc trên để đánh dấu lại vị trí ưa thích. Sau này có thể truy cập lại thông qua Menu Bookmark.',
    },
    {
      'question': 'Làm sao để theo dõi & nhận thông báo?',
      'answer':
          '- Theo dõi: Click icon ❤️ ở trang chi tiết, truyện sẽ vào thư viện "Theo dõi".\n'
          '- Thông báo: Click icon 🔔 để nhận cảnh báo khi có Chapter mới.\n\n'
          'Lưu ý: Bạn cần đăng nhập để sử dụng tính năng này.',
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
      'description': 'Hỗ trợ PDF, EPUB, ZIP, Tiểu thuyết',
      'content':
          '📖 ĐỌC TRUYỆN ĐA ĐỊNH DẠNG\n\n'
          '1️⃣ TRUYỆN TRANH (ZIP, CBZ, EPUB)\n'
          '   • Vuốt trái/phải để sang trang\n'
          '   • Dùng phím Âm lượng để chuyển trang\n'
          '   • Double tap để phóng to nhanh\n\n'
          '2️⃣ ĐỌC SÁCH PDF\n'
          '   • Tối ưu hoá cực tốt cho file nặng >50MB\n'
          '   • Dùng 2 ngón tay (Pinch) để phóng to/thu nhỏ thoải mái\n'
          '   • Vuốt dọc để cuộn trang mượt mà\n\n'
          '3️⃣ TIỂU THUYẾT (TXT, NOVEL)\n'
          '   • Chạm giữa màn hình để mở Bảng điều khiển\n'
          '   • Tuỳ chỉnh Font chữ, Cỡ chữ to/nhỏ\n'
          '   • Thay đổi Màu nền (Trắng/Đen/Vàng) cho đỡ mỏi mắt\n\n'
          '4️⃣ ĐIỀU HƯỚNG & BOOKMARK\n'
          '   • Thanh Slider dưới đáy: Kéo nhanh đến trang mong muốn\n'
          '   • Nút Bookmark: Lưu lại vị trí trang hay\n'
          '   • Tiến trình đọc luôn được lưu tự động!',
    },
    {
      'title': 'Giao lưu tại Diễn đàn',
      'description': 'Chat tổng, Đăng bài, Bình luận & Thả tim',
      'content':
          '🌐 THAM GIA DIỄN ĐÀN\n\n'
          '1️⃣ CHAT TỔNG (GLOBAL CHAT)\n'
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
    final filteredFAQs = _faqs.where((faq) {
      return faq['question']!.toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ) ||
          faq['answer']!.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1C),
        title: const Text('Trợ giúp'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSearchBar(),
          const SizedBox(height: 24),

          _buildSectionHeader('❓ Câu hỏi thường gặp'),
          const SizedBox(height: 8),
          ...filteredFAQs.map((faq) => _buildFAQItem(faq)),

          const SizedBox(height: 24),

          _buildSectionHeader('📖 Hướng dẫn sử dụng'),
          const SizedBox(height: 8),
          ..._guides.map((guide) => _buildGuideItem(guide)),

          const SizedBox(height: 24),
          _buildSectionHeader('📧 Liên hệ hỗ trợ'),
          const SizedBox(height: 8),
          _buildContactInfo(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: '🔍 Tìm kiếm...',
        hintStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF1A1A1C),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        prefixIcon: const Icon(Icons.search, color: Colors.grey),
      ),
      onChanged: (value) => setState(() => _searchQuery = value),
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
      color: const Color(0xFF1A1A1C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(
          faq['question']!,
          style: const TextStyle(
            color: Colors.white,
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
      color: const Color(0xFF1A1A1C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.book, color: Colors.orange),
        title: Text(
          guide['title']!,
          style: const TextStyle(color: Colors.white),
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
        backgroundColor: const Color(0xFF2C2C2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.book, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                guide['title']!,
                style: const TextStyle(
                  color: Colors.white,
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
            style: const TextStyle(color: Colors.white70, height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  Widget _buildContactInfo() {
    return Card(
      color: const Color(0xFF1A1A1C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.email, color: Colors.orange),
            title: const Text('Email', style: TextStyle(color: Colors.white)),
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
          const Divider(color: Colors.grey),
          ListTile(
            leading: const Icon(Icons.facebook, color: Colors.orange),
            title: const Text(
              'Facebook',
              style: TextStyle(color: Colors.white),
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
