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
      'question': 'Làm sao để đọc truyện?',
      'answer':
          '1. Chọn truyện từ trang chủ\n'
          '2. Click vào chapter muốn đọc\n'
          '3. Swipe sang trái/phải để chuyển trang\n'
          '4. Pinch để zoom ảnh',
    },
    {
      'question': 'Làm sao để bật thông báo chapter mới?',
      'answer':
          '1. Vào trang chi tiết truyện\n'
          '2. Click icon 🔔 ở góc trên bên phải\n'
          '3. ✅ Bạn sẽ nhận thông báo khi có chapter mới!\n\n'
          'Lưu ý: Bạn cần đăng nhập để sử dụng tính năng này.',
    },
    {
      'question': 'Làm sao để xem thông báo?',
      'answer':
          'Click icon 🔔 ở góc trên bên phải trang chủ.\n\n'
          'Badge đỏ hiện số thông báo chưa đọc.\n'
          'Click vào thông báo để xem chi tiết truyện.',
    },
    {
      'question': 'Làm sao để theo dõi truyện?',
      'answer':
          'Click vào icon ❤️ ở góc trên bên phải trang chi tiết truyện.\n\n'
          'Truyện sẽ được thêm vào thư viện của bạn và hiển thị ở tab "Theo dõi".',
    },
    {
      'question': 'Làm sao để đổi mật khẩu?',
      'answer':
          'Vào Settings → Tài khoản → Đổi mật khẩu\n\n'
          'Nhập mật khẩu cũ và mật khẩu mới để thay đổi.',
    },
    {
      'question': 'Làm sao để đăng nhập bằng Google?',
      'answer':
          'Ở trang đăng nhập:\n'
          '1. Click nút "Đăng nhập bằng Google"\n'
          '2. Chọn tài khoản Google của bạn\n'
          '3. ✅ Đăng nhập thành công!\n\n'
          'Bạn có thể thêm mật khẩu sau ở Settings → Thêm mật khẩu.',
    },
    {
      'question': 'Tại sao không thấy truyện mới?',
      'answer':
          'Kéo xuống ở trang chủ để refresh danh sách truyện mới nhất.\n\n'
          'Nếu vẫn không thấy, kiểm tra kết nối internet của bạn.',
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
          '3️⃣ Nhập thông tin:\n'
          '   • Email: Địa chỉ email hợp lệ\n'
          '   • Mật khẩu: Tối thiểu 6 ký tự\n'
          '   • Xác nhận mật khẩu: Nhập lại mật khẩu\n'
          '4️⃣ Click nút "Đăng ký"\n'
          '5️⃣ Kiểm tra email để xác thực tài khoản\n'
          '6️⃣ Click link xác thực trong email\n'
          '7️⃣ ✅ Hoàn tất! Đăng nhập để sử dụng\n\n'
          '🔐 ĐĂNG NHẬP BẰNG GOOGLE\n\n'
          '1️⃣ Tại màn hình đăng nhập\n'
          '2️⃣ Click "Đăng nhập bằng Google"\n'
          '3️⃣ Chọn tài khoản Google của bạn\n'
          '4️⃣ ✅ Đăng nhập thành công!\n\n'
          '💡 LƯU Ý:\n'
          '• Mật khẩu phải có ít nhất 6 ký tự\n'
          '• Email phải là địa chỉ hợp lệ\n'
          '• Nếu đăng nhập bằng Google, bạn có thể thêm mật khẩu sau ở Settings',
    },
    {
      'title': 'Đọc truyện',
      'description': 'Cách đọc và điều hướng trong truyện',
      'content':
          '📖 ĐỌC TRUYỆN\n\n'
          '1️⃣ TÌM TRUYỆN\n'
          '   • Trang chủ: Xem truyện mới nhất\n'
          '   • Tìm kiếm: Click icon 🔍 để tìm truyện\n'
          '   • Thể loại: Lọc theo thể loại yêu thích\n\n'
          '2️⃣ XEM CHI TIẾT TRUYỆN\n'
          '   • Click vào truyện để xem thông tin\n'
          '   • Xem mô tả, tác giả, thể loại\n'
          '   • Danh sách chapters\n'
          '   • Số người theo dõi\n\n'
          '3️⃣ ĐỌC CHAPTER\n'
          '   • Click vào chapter muốn đọc\n'
          '   • Swipe trái/phải để chuyển trang\n'
          '   • Pinch (2 ngón tay) để zoom ảnh\n'
          '   • Double tap để zoom nhanh\n\n'
          '4️⃣ ĐIỀU HƯỚNG\n'
          '   • Swipe phải: Trang trước\n'
          '   • Swipe trái: Trang sau\n'
          '   • Click giữa màn hình: Hiện/ẩn controls\n'
          '   • Slider dưới: Nhảy đến trang bất kỳ\n\n'
          '5️⃣ THEO DÕI TRUYỆN\n'
          '   • Click icon ❤️ để theo dõi\n'
          '   • Truyện sẽ lưu vào thư viện\n'
          '   • Xem lại ở tab "Theo dõi"\n\n'
          '6️⃣ BẬT THÔNG BÁO\n'
          '   • Click icon 🔔 ở trang chi tiết\n'
          '   • Nhận thông báo khi có chapter mới\n\n'
          '💡 MẸO:\n'
          '• Lịch sử đọc tự động lưu\n'
          '• Kéo xuống trang chủ để refresh\n'
          '• Đọc offline (nếu đã tải)',
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
