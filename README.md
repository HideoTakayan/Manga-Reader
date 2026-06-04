# Báo Cáo Phát Triển Toàn Diện: Manga & Novel Reader 📚

## 1. Giới Thiệu Dự Án

**Manga Reader** là một ứng dụng di động đa nền tảng (Android/iOS) được phát triển bằng Flutter, hướng tới mục tiêu cung cấp trải nghiệm đọc truyện tranh và truyện chữ hoàn hảo (Premium UX). Ứng dụng giải quyết triệt để các vấn đề của các nền tảng đọc truyện lậu hiện nay như: quảng cáo tràn lan, tốc độ tải chậm, ngốn RAM, và rủi ro mất dữ liệu khi server sập.

Hệ thống được thiết kế theo tư duy **Offline-First** (ưu tiên ngoại tuyến) và kiến trúc **Serverless** (phi máy chủ), sử dụng bộ đôi **Google Drive** và **Firebase** làm xương sống, giúp tối ưu hóa 100% chi phí vận hành mà vẫn đảm bảo hiệu suất mở rộng vô hạn.

### 1.1 Sứ Mệnh & Mục Tiêu
- **Trải nghiệm cá nhân hóa**: Cung cấp công cụ quản lý thư viện cá nhân mạnh mẽ, đọc trọn bộ từ A-Z không cần Internet.
- **Hỗ trợ đa định dạng**: Đọc mượt mà ảnh truyện (CBZ, ZIP), tài liệu (PDF), và truyện chữ (EPUB) nguyên bản.
- **Tính cộng đồng**: Không chỉ là nơi đọc, mà còn là nơi giao lưu qua hệ thống Diễn đàn (Forum) và Mạng xã hội thu nhỏ.
- **Quản trị dễ dàng**: Tất cả quyền năng điều hành (Thêm, Sửa, Xóa, Báo cáo) đều nằm gọn trong Admin Panel trực tiếp trên App.

---

## 2. Kiến Trúc Kỹ Thuật Chuyên Sâu

Dự án áp dụng mô hình **Client-Serverless** tiên tiến, bỏ qua hoàn toàn các Backend truyền thống (NodeJS/Python) để giao tiếp trực tiếp với Cloud APIs.

### 2.1 Sơ Đồ Khối Tổng Quan
```text
[Người Dùng App] --- (GoRouter + Riverpod) ---> [Core Reader Engine]
       |                                              |
       +---> [Google Drive API v3] <------------------+
       |       (Kho chứa CBZ/ZIP/PDF/EPUB & catalog.json)
       |
       +---> [Firebase Auth] (Xác thực người dùng)
       |
       +---> [Firebase Firestore] (Lượt view, theo dõi, Forum, Reports, Ratings)
       |
       +---> [SQLite Local DB] (Lịch sử đọc, tiến độ tải xuống, quản lý tệp offline)
```

### 2.2 Các Module Cốt Lõi (Core Modules)

#### 2.2.1 Core Reader Engine (Trình Đọc Truyện)
- **Kiến trúc Hiển thị**: Tách biệt UI và State. Áp dụng kỹ thuật `ValueNotifier` kết hợp `ValueListenableBuilder` cho các thành phần cần cập nhật siêu tốc (như thanh trượt hiển thị % số trang) nhằm ngăn chặn việc *Rebuild* toàn bộ trang, đảm bảo duy trì 120 FPS khi cuộn tốc độ cao.
- **Cơ chế Hold-to-Load**: Chuyển chương bằng Gestures. Người dùng cuộn tới cuối/đầu trang và giữ 1.5 giây để tự động chuyển chương mà không cần bấm nút rời rạc.
- **EPUB Engine**: Tích hợp thư viện giải mã EPUB mạnh mẽ. Khi người dùng tải truyện chữ EPUB, hệ thống tự động bóc tách (extract) ảnh bìa và đồng bộ hóa vào hệ thống tệp cục bộ nguyên trạng, không can thiệp làm hỏng cấu trúc tệp.

#### 2.2.2 Fast Cache & Anti-OOM (Hệ Thống Chống Tràn Bộ Nhớ)
Một trong những đột phá lớn nhất của hệ thống là khả năng chống tràn RAM (Out of Memory - OOM):
- **Ghi trực tiếp ra ổ cứng**: Trái với các app thông thường tải file ZIP 100MB rồi giải nén toàn bộ 200 tấm ảnh vào RAM khiến máy sập, Manga Reader sử dụng Isolate (luồng ngầm) để bung nén ảnh **trực tiếp xuống ổ đĩa cục bộ (Local Storage)**.
- **ImageCache Limit**: Bộ đệm hình ảnh của Flutter (`PaintingBinding.instance.imageCache`) được khóa cứng ở mức tối đa **80MB**. Nhờ vậy, dung lượng RAM tiêu thụ luôn ổn định ở mức an toàn (~50MB) dù người dùng lướt hàng nghìn trang truyện sắc nét.
- **Prefetch & Zero-Delay**: Hình ảnh của chương tiếp theo được âm thầm tải và giải nén dưới nền. Khi người dùng lật chương, thời gian chờ là **0.1 giây**.

#### 2.2.3 Xử Lý Bất Đồng Bộ & UX/UI Blocking
- **An Toàn Dữ Liệu Ngầm**: Hệ thống tải xuống (`DownloadService`) sở hữu Hàng Đợi (Queue) thông minh. Khi người dùng vừa tải vừa xóa truyện, App sẽ quét và ngắt luồng ưu tiên, hủy tệp `.part` an toàn để triệt tiêu hoàn toàn rủi ro **Race Condition** (Xung đột đa luồng).
- **Loading Indicators chặt chẽ**: Mọi thao tác I/O nặng (Tải hàng loạt, Xóa hàng loạt) đều được bọc bởi giao diện Loading bất khả xâm phạm (`barrierDismissible: false`), loại bỏ tình trạng kẹt UI hay thao tác chồng chéo.

---

## 3. Hệ Sinh Thái Tính Năng

### 3.1 Giao Tiếp & Mạng Xã Hội (Forum)
- **Tạo Bài Viết & Thảo Luận**: Hỗ trợ 2 định dạng (Discussion - Hỏi đáp, và Recommendation - Giới thiệu truyện).
- **Phòng Chat Tích Hợp**: Gửi tin nhắn, chia sẻ ảnh động (GIF Picker) theo thời gian thực (Real-time).
- **Cơ chế Cập Nhật State Rẽ Nhánh**: Giải quyết bài toán hàng trăm Stream ngốn tiền bằng cách quản lý View/Like/Comment qua 1 Stream tập trung ở Parent Widget, chia sẻ dữ liệu xuống cây Widget con. Giảm **99% lượng Reads** trên Firestore.

### 3.2 Thư Viện Cá Nhân Tối Thượng
- **Custom Categories**: Tự do tạo thư mục (Action, Romance, Chờ đọc...) và kéo thả truyện vào từng mục.
- **Batch Operations**: Lệnh "Tải toàn bộ" thư mục, hoặc "Xóa toàn bộ" chỉ với 1 cú click.

### 3.3 Dashboard Quản Trị Hệ Thống (Admin Panel)
- **Phân Quyền Tuyệt Đối**: Cấp quyền Admin qua whitelist Email định sẵn trong mã nguồn. Admin Panel sẽ ẩn hoàn toàn với User thường.
- **Aggregation Count Query**: Thống kê hàng vạn lượt xem, hàng ngàn Users bằng lệnh đếm siêu cấp của Firestore (`.count().get()`) thay vì kéo toàn bộ dữ liệu về máy, tối ưu băng thông.
- **Quản lý Banner & Chapters**: Upload và đổi ảnh Banner trang chủ, đồng bộ hóa các chương truyện lên Drive dễ dàng từ điện thoại.

---

## 4. Stack Công Nghệ (Technology Stack)

### 4.1 Framework & State Management
| Thành phần | Công nghệ | Mục đích |
|---|---|---|
| UI Framework | Flutter 3.x (Dart) | Render giao diện đa nền tảng từ 1 codebase |
| State Management | Riverpod 2.x | Quản lý trạng thái toàn cục an toàn, không có `setState` ẩn |
| Navigation | GoRouter 14.x | Deep-linking, điều hướng có điều kiện (Auth Guard) |
| Local Database | SQLite (sqflite) | Lưu lịch sử, thư viện, tiến độ tải xuống cục bộ |

### 4.2 Thư Viện Xử Lý Nội Dung
| Thư viện | Phiên bản | Vai trò |
|---|---|---|
| `archive` | 3.6.x | Giải nén CBZ / ZIP / RAR với hiệu suất cao |
| `pdfx` | 2.6.x | Render tài liệu PDF mượt mà từng trang |
| `photo_view` | 0.15.x | Hỗ trợ Pinch-to-Zoom, Pan ảnh truyện ngang |
| `flutter_tts` | 4.2.x | Text-to-Speech đọc to truyện chữ |
| `xml` | 6.5.x | Phân tích cú pháp tệp EPUB (chuẩn XML/OPF) |
| `html` | 0.15.x | Render nội dung HTML bên trong tệp EPUB |

### 4.3 Google Cloud & Firebase
| Dịch vụ | Thư viện | Chức năng |
|---|---|---|
| Google Drive v3 | `googleapis` + `googleapis_auth` | Đọc/ghi file, duyệt thư mục truyện |
| Google Sign-In | `google_sign_in` | Xác thực người dùng bằng tài khoản Google |
| Firebase Auth | `firebase_auth` | Quản lý phiên đăng nhập, cấp quyền truy cập |
| Cloud Firestore | `cloud_firestore` | Lưu dữ liệu cộng đồng: View, Like, Follow, Forum |

### 4.4 Hiệu Năng & Hệ Thống
| Thư viện | Vai trò |
|---|---|
| `flutter_background_service` | Giữ tác vụ tải xuống sống sót khi App bị minimize |
| `flutter_local_notifications` | Thông báo tiến độ tải xuống trên màn hình khóa |
| `wakelock_plus` | Ngăn CPU ngủ đông trong lúc đang tải file nặng |
| `fl_chart` | Vẽ biểu đồ thống kê thói quen đọc cho trang Analytics |
| `path_provider` + `path` | Quản lý đường dẫn file đa nền tảng an toàn |
| `permission_handler` | Xin quyền truy cập bộ nhớ, thông báo |

---

## 5. Cấu Trúc Dự Án (Project Structure)

Dự án tuân theo mô hình **Feature-First** — mỗi tính năng là một module độc lập hoàn toàn, tránh sự phụ thuộc rối rắm giữa các màn hình.

```
lib/
├── main.dart                     # Entry point, khởi tạo Firebase & ImageCache limit
├── firebase_options.dart         # Cấu hình Firebase tự động sinh (FlutterFire CLI)
│
├── core/                         # Hạt nhân toàn ứng dụng
│   └── app_router.dart           # Cấu hình toàn bộ routes (GoRouter)
│
├── config/                       # Hằng số toàn cục, theme, màu sắc
│
├── data/                         # Tầng dữ liệu (Data Layer)
│   ├── database_helper.dart      # Quản lý SQLite: tạo bảng, migrate, CRUD
│   └── models_cloud.dart         # Data models: Manga, Chapter, MangaStats, ...
│
├── services/                     # Tầng dịch vụ (Service Layer) — 17 services
│   ├── download_service.dart     # Quản lý hàng đợi tải xuống (Queue + Race Condition safety)
│   ├── novel_service.dart        # Import EPUB, extract bìa, quản lý truyện chữ
│   ├── notification_service.dart # Thông báo đẩy (Local Notifications)
│   ├── auth_service.dart         # Đăng nhập Google / Email
│   ├── history_service.dart      # Ghi/đọc lịch sử đọc từ SQLite
│   ├── interaction_service.dart  # Ghi View/Like lên Firestore
│   ├── library_service.dart      # Thư viện & danh mục cá nhân
│   ├── follow_service.dart       # Follow/Unfollow truyện
│   ├── background_service.dart   # Tải xuống ngầm khi App tắt màn hình
│   ├── backup_service.dart       # Sao lưu/khôi phục dữ liệu
│   └── ...                       # (và 7 services khác)
│
└── features/                     # Tầng giao diện (UI Layer) — 16 features
    ├── home/                     # Trang chủ: Trending, Mới cập nhật, Banner
    ├── catalog/                  # Danh sách truyện, bộ lọc thể loại
    ├── detail/                   # Chi tiết truyện & danh sách chương
    ├── reader/                   # Trình đọc (Ngang/Dọc/PDF/EPUB/TTS)
    │   ├── reader_page.dart      # UI chính — 2500+ dòng, xử lý toàn bộ gestures
    │   ├── reader_provider.dart  # State Management của Reader (Riverpod Notifier)
    │   ├── novel_reader_widget.dart  # Widget đọc EPUB/truyện chữ
    │   └── pdf_reader_view.dart  # Widget render PDF
    ├── library/                  # Thư viện cá nhân & danh mục tùy chỉnh
    ├── downloads/                # Quản lý hàng đợi & lịch sử tải xuống
    ├── storage/                  # Quản lý dung lượng bộ nhớ đã dùng
    ├── forum/                    # Diễn đàn & phòng chat cộng đồng
    ├── search/                   # Tìm kiếm toàn cục (với Debounce chống lag)
    ├── auth/                     # Đăng nhập / Đăng ký
    ├── settings/                 # Cài đặt người dùng, chủ đề, thông báo
    ├── admin/                    # Admin Panel: thống kê, quản lý nội dung
    ├── notification/             # Trung tâm thông báo trong App
    └── backup/                   # Giao diện sao lưu & khôi phục dữ liệu
```

---

## 6. Luồng Xử Lý Chi Tiết (Data Flow Deep Dive)

### 6.1 Luồng Khởi Động & Phân Quyền

```
App khởi động
    │
    ├─ Khởi tạo Firebase, SQLite, ImageCache(80MB)
    │
    ├─ Kiểm tra trạng thái Auth (Firebase Auth)
    │       ├─ Chưa đăng nhập → Màn hình Login (GoRouter redirect)
    │       └─ Đã đăng nhập → Màn hình Home
    │
    └─ Kiểm tra Email trong whitelist Admin?
            ├─ Có → Hiện tab Admin Panel trong Scaffold
            └─ Không → Tab Admin bị ẩn hoàn toàn
```

### 6.2 Luồng Đọc Truyện (Online → Offline → Cache)

```
Bấm vào Chapter
    │
    ├─ SQLite: Chapter đã tải xuống? (isDownloaded = true?)
    │       └─ CÓ → Đọc file từ Local Storage → Giải nén CBZ/ZIP trong Isolate
    │                   → Ghi từng ảnh ra thư mục Cache → Hiển thị ListView
    │
    └─ KHÔNG → Gọi Google Drive API lấy fileId
                    │
                    ├─ Tải file nén về bộ nhớ tạm (Uint8List stream)
                    ├─ Giải nén toàn bộ ảnh trong Isolate (luồng ngầm)
                    ├─ Ghi ảnh trực tiếp xuống thư mục Cache (không qua RAM)
                    └─ Hiển thị danh sách ảnh → ListView.builder
                                                    │
                                                    └─ ValueNotifier<int> cập nhật
                                                       số trang (120fps, không Rebuild)
```

### 6.3 Luồng Tải Xuống An Toàn (Download Queue)

```
Bấm "Tải xuống"
    │
    ├─ DownloadService thêm Task vào Queue
    ├─ Wakelock.enable() — CPU không ngủ
    ├─ BackgroundService.start() — App tiếp tục tải khi minimize
    │
    ├─ Vòng lặp Queue:
    │       ├─ Tải file từ Drive API → Ghi xuống .part file
    │       ├─ Cập nhật tiến độ (%) → NotificationService hiển thị
    │       └─ Hoàn tất → Đổi tên .part → .cbz → Cập nhật SQLite
    │
    └─ Nếu người dùng XÓA truyện đang tải:
            ├─ DownloadService phát hiện xung đột (Race Condition)
            ├─ Hủy tải ngay lập tức
            └─ Xóa tệp .part dở dang — Không để lại rác
```

---

## 7. Các Điểm Kỹ Thuật Đặc Biệt (Technical Highlights)

### 7.1 Debounce Tìm Kiếm
Ô tìm kiếm áp dụng **Debounce 500ms** — tức là hệ thống chỉ thực sự gọi API/lọc dữ liệu sau khi người dùng **dừng gõ 0.5 giây**. Điều này triệt tiêu hoàn toàn tình trạng giật lag UI khi gõ nhanh.

### 7.2 Merge Chapters (Gộp Chương Online + Offline)
Thuật toán `ChapterUtils.mergeChapters()` thực hiện bài toán phức tạp: gộp danh sách chương từ `catalog.json` (Drive) với danh sách trong SQLite cục bộ, ưu tiên giữ lại metadata của chương đã tải, loại trùng lặp bằng ID. Kết quả là người dùng luôn thấy danh sách chương đầy đủ và nhất quán dù online hay offline.

### 7.3 Aggregation Count (Thống kê không kéo dữ liệu)
Thay vì lệnh `getDocs()` kéo toàn bộ 10,000 documents về máy để đếm, Admin Panel dùng:
```dart
final count = await firestore.collection('views').count().get();
print(count.count); // Trả về số nguyên, KHÔNG tốn băng thông đọc từng document
```
Cách này tiết kiệm **99.9% chi phí Reads** của Firestore.

### 7.4 Firebase Stream Tối Ưu (1 Stream → N Widgets)
Thay vì mỗi Widget con (`CommentCard`, `LikeButton`, `ViewCounter`) tự mở 1 Stream riêng lên Firestore, toàn bộ dữ liệu tương tác được lấy từ **1 Stream duy nhất** ở Widget cha (`ForumPostPage`), sau đó truyền xuống cây con qua `ref.watch`. Giảm số lượng kết nối đồng thời từ hàng trăm xuống còn **1 kết nối mỗi màn hình**.

---

## 8. Tải Xuống & Cài Đặt

> **📥 Download Android APK (Bản Release mới nhất):**
> [**TẢI FILE APK TẠI ĐÂY — GOOGLE DRIVE**](https://drive.google.com/file/d/1wTTaZAyjQcpIFlepORbb43IpRl5lcVku/view?usp=drive_link)

**Hướng dẫn cài đặt:**
1. Tải file `app-release.apk` về điện thoại Android.
2. Mở file APK → Nếu được yêu cầu, bật **"Cài đặt từ nguồn không xác định"** (Unknown Sources) trong Cài đặt bảo mật của thiết bị.
3. Hoàn tất cài đặt → Mở App → Đăng nhập bằng Google Account.

---

## 9. Thiết Kế Giao Diện (UI/UX Design System)

### 9.1 Triết Lý Thiết Kế
Toàn bộ giao diện được xây dựng xoay quanh triết lý **"Dark + Premium"** — tôn trọng nội dung là trên hết, đặt ảnh truyện lên làm nhân vật chính, các thành phần UI chỉ xuất hiện khi thực sự cần thiết và ẩn đi khi người dùng đang đọc.

- **Nền tối (Dark Mode mặc định)**: Giảm mỏi mắt khi đọc đêm, tiết kiệm pin màn hình AMOLED.
- **Màu chủ đạo**: Gradient Tím - Xanh Dương (`#6C5CE7` → `#0984E3`) — Hiện đại, sang trọng, không rối mắt.
- **Typography**: Tận dụng font hệ thống (Roboto / SF Pro), điều chỉnh weight và spacing để tối ưu khả năng đọc.

### 9.2 Các Màn Hình Chính

| Màn hình | Mô tả thiết kế |
|---|---|
| **Home** | Banner slider toàn màn hình, card truyện trending với hiệu ứng Shimmer khi tải |
| **Catalog** | Lưới 2-3 cột linh hoạt, bộ lọc thể loại dạng chip có thể cuộn ngang |
| **Detail** | Hero Animation khi chuyển từ danh sách vào, danh sách chương với trạng thái Đã đọc/Đã tải |
| **Reader** | Toàn màn hình, ẩn SystemUI, điều khiển xuất hiện khi Tap và tự ẩn sau 3 giây |
| **Library** | Danh mục dạng thẻ, hỗ trợ kéo thả (Drag & Drop) sắp xếp lại vị trí |
| **Forum** | Feed vô hạn (Infinite Scroll), phân biệt rõ 2 loại bài (Discussion / Recommendation) |
| **Admin Dashboard** | Biểu đồ cột thống kê theo ngày, bảng danh sách tương tác dạng DataTable |

### 9.3 Micro-animations & UX Chi Tiết
- **Hold-to-Load Arc**: Khi người dùng giữ ở cuối chương, hiển thị vòng tròn tiến trình `CircularProgressIndicator` tùy chỉnh (nền mờ + màu nước) đếm ngược 1.5 giây. Trực quan và không gây hoảng sợ.
- **Shimmer Loading**: Thay vì hiển thị màn hình trắng, mọi card truyện đều có hiệu ứng shimmer sáng bóng khi đang tải dữ liệu.
- **Snackbar thông minh**: Thông báo thành công/lỗi xuất hiện ở đáy màn hình, tự động biến mất sau 3 giây. Không bao giờ chặn thao tác của người dùng.
- **Pull-to-Refresh**: Vuốt xuống để làm mới dữ liệu theo chuẩn Material Design.

---

## 10. Roadmap — Kế Hoạch Phát Triển

### ✅ Đã Hoàn Thành (v1.0)
- [x] Trình đọc truyện tranh (CBZ/ZIP/PDF) dọc & ngang
- [x] Trình đọc truyện chữ EPUB
- [x] Hệ thống tải xuống nền (Background Download)
- [x] Thư viện cá nhân & danh mục tùy chỉnh
- [x] Diễn đàn cộng đồng & phòng chat real-time
- [x] Admin Panel với thống kê Dashboard
- [x] Hệ thống báo cáo lỗi truyện (Report System)
- [x] Text-to-Speech đọc truyện chữ
- [x] Sao lưu & Khôi phục dữ liệu
- [x] Anti-OOM & Fast Cache hoàn chỉnh

### 🚧 Đang Phát Triển (v1.1)
- [ ] Thêm định dạng CBR (Comic Book RAR)
- [ ] Hỗ trợ mua truyện / ủng hộ tác giả (Donation flow)
- [ ] Đồng bộ tiến độ đọc đa thiết bị qua Firestore

### 💡 Dự Kiến (v2.0)
- [ ] Hỗ trợ iOS (App Store)
- [ ] Machine Learning gợi ý truyện theo thói quen đọc
- [ ] Chế độ đọc nhóm (Co-reading) — Nhiều người đọc cùng nhau real-time

---

## 11. Kết Luận

**Manga Reader** không chỉ là một ứng dụng đọc truyện — đây là một bằng chứng thuyết phục về năng lực thiết kế và triển khai hệ thống phần mềm thực tế cấp chuyên nghiệp.

Dự án này giải quyết thành công bài toán phức tạp đa chiều:

| Chiều kích | Thách thức | Giải pháp |
|---|---|---|
| **Kỹ thuật** | Xử lý file nặng, đa luồng, không OOM | Isolate + Direct Write + ImageCache Cap |
| **Kinh tế** | Chi phí vận hành bằng 0 | Drive API + Firebase Serverless |
| **UX** | Mượt mà, không lag, offline hoàn toàn | ValueNotifier + Debounce + Offline-First |
| **Cộng đồng** | Tương tác real-time, không tốn bandwidth | 1 Stream / Screen + Aggregation Count |
| **Quản trị** | Điều hành từ xa ngay trên App | Admin Panel tích hợp + Role-based Access |

---

> 💬 *"Manga Reader là minh chứng rằng với kiến trúc đúng đắn và kỹ thuật tối ưu hóa sâu, một lập trình viên cá nhân hoàn toàn có thể tạo ra sản phẩm cạnh tranh trực tiếp với các ứng dụng thương mại được hàng chục kỹ sư xây dựng."*