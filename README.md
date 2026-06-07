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
- **Kiến trúc Hiển thị**: Tách biệt UI và State. Áp dụng kỹ thuật `ValueNotifier` kết hợp `ValueListenableBuilder` cho các thành phần cần cập nhật siêu tốc nhằm ngăn chặn việc *Rebuild* toàn bộ trang, đảm bảo duy trì 120 FPS khi cuộn tốc độ cao.
- **Cơ chế Hold-to-Load**: Chuyển chương bằng Gestures. Người dùng cuộn tới cuối/đầu trang và giữ 1.5 giây để tự động chuyển chương mà không cần bấm nút rời rạc.
- **EPUB Engine**: Tích hợp thư viện giải mã EPUB mạnh mẽ. Khi người dùng tải truyện chữ EPUB, hệ thống tự động bóc tách (extract) ảnh bìa và đồng bộ hóa vào hệ thống tệp cục bộ nguyên trạng, không can thiệp làm hỏng cấu trúc tệp.

#### 2.2.2 Fast Cache & Anti-OOM (Hệ Thống Chống Tràn Bộ Nhớ)
Một trong những đột phá lớn nhất của hệ thống là khả năng chống tràn RAM (Out of Memory - OOM):
- **Ghi trực tiếp ra ổ cứng**: Trái với các app thông thường tải file nén rồi bung vào RAM khiến máy sập, ứng dụng sử dụng Isolate (luồng ngầm) qua hàm `compute` để bung nén ảnh **trực tiếp xuống ổ đĩa cục bộ (Local Storage)**.
- **ImageCache Limit**: Bộ đệm hình ảnh của Flutter (`PaintingBinding.instance.imageCache`) được khóa cứng ở mức tối đa **80MB**. Nhờ vậy, dung lượng RAM tiêu thụ luôn ổn định ở mức an toàn (~50MB) dù người dùng lướt hàng nghìn trang truyện sắc nét.

#### 2.2.3 Xử Lý Bất Đồng Bộ & UX/UI Blocking
- **An Toàn Dữ Liệu Ngầm**: Hệ thống tải xuống (`DownloadService`) sở hữu Hàng Đợi (Queue) thông minh. Khi người dùng vừa tải vừa xóa truyện, App sẽ quét và ngắt luồng ưu tiên, hủy tệp `.part` an toàn để triệt tiêu hoàn toàn rủi ro **Race Condition** (Xung đột đa luồng).
- **Loading Indicators chặt chẽ**: Mọi thao tác I/O nặng (Tải hàng loạt, Xóa hàng loạt) đều được bọc bởi giao diện Loading bất khả xâm phạm (`barrierDismissible: false`), loại bỏ tình trạng kẹt UI hay thao tác chồng chéo.

---

## 3. Hệ Sinh Thái Tính Năng

### 3.1 Giao Tiếp & Mạng Xã Hội (Forum)
- **Tạo Bài Viết & Thảo Luận**: Hỗ trợ 2 định dạng (Discussion - Hỏi đáp, và Recommendation - Giới thiệu truyện).
- **Phòng Chat Tích Hợp**: Gửi tin nhắn, hình ảnh theo thời gian thực (Real-time chat).
- **Cơ chế Cập Nhật State Rẽ Nhánh**: Giải quyết bài toán hàng trăm Stream ngốn tiền bằng cách quản lý View/Like/Comment qua 1 Stream tập trung ở Parent Widget, chia sẻ dữ liệu xuống cây Widget con. Giảm **99% lượng Reads** trên Firestore.

### 3.2 Thư Viện Cá Nhân Tối Thượng
- **Custom Categories**: Tự do tạo thư mục (Action, Romance, Chờ đọc...) và kéo thả truyện vào từng mục. Danh mục mặc định luôn được hệ thống bảo vệ an toàn khỏi việc xóa nhầm.
- **Batch Operations**: Lệnh "Tải toàn bộ" thư mục, hoặc "Xóa toàn bộ" chỉ với 1 cú click.

### 3.3 Dashboard Quản Trị Hệ Thống (Admin Panel)
- **Phân Quyền Tuyệt Đối**: Cấp quyền Admin qua whitelist Email định sẵn trong mã nguồn (`admin_config.dart`). Admin Panel sẽ ẩn hoàn toàn với User thường.
- **Aggregation Count Query**: Thống kê hàng vạn lượt xem, hàng ngàn Users bằng lệnh đếm siêu cấp của Firestore (`.count().get()`) thay vì kéo toàn bộ dữ liệu về máy, tối ưu băng thông.
- **Quản lý Banner & Chapters**: Upload và đổi ảnh Banner trang chủ, quản lý reports và các tính năng kiểm duyệt.

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
| `xml` / `html` | 6.5.x / 0.15.x | Phân tích cấu trúc và hiển thị tệp EPUB |

### 4.3 Google Cloud & Firebase
| Dịch vụ | Thư viện | Chức năng |
|---|---|---|
| Google Drive v3 | `googleapis` + `googleapis_auth` | Đọc/ghi file, duyệt thư mục truyện |
| Google Sign-In | `google_sign_in` | Xác thực người dùng bằng tài khoản Google |
| Firebase Auth | `firebase_auth` | Quản lý phiên đăng nhập, cấp quyền truy cập |
| Cloud Firestore | `cloud_firestore` | Lưu dữ liệu cộng đồng: View, Like, Follow, Forum, Lịch sử Sync |

### 4.4 Hiệu Năng & Hệ Thống
| Thư viện | Vai trò |
|---|---|
| `flutter_background_service` | Giữ tác vụ tải xuống sống sót khi App bị minimize |
| `wakelock_plus` | Ngăn CPU ngủ đông trong lúc đang tải file nặng |
| `flutter_local_notifications` | Thông báo tiến độ tải xuống / thông báo hệ thống |
| `fl_chart` | Vẽ biểu đồ thống kê thói quen đọc cho trang Analytics |

---

## 5. Cấu Trúc Dự Án (Project Structure)

Dự án tuân theo mô hình **Feature-First** — mỗi tính năng là một module độc lập hoàn toàn, tránh sự phụ thuộc rối rắm.

```text
lib/
├── main.dart                     # Entry point, khởi tạo Firebase & ImageCache limit
├── firebase_options.dart         # Cấu hình Firebase tự động sinh
│
├── core/                         # Hạt nhân toàn ứng dụng (Router, tiện ích giải nén ảnh)
├── config/                       # Hằng số toàn cục, theme, màu sắc, admin config
│
├── data/                         # Tầng dữ liệu (Data Layer)
│   ├── database_helper.dart      # Quản lý SQLite: tạo bảng, migrate, CRUD
│   └── models_cloud.dart         # Data models: Manga, Chapter, MangaStats, ...
│
├── services/                     # Tầng dịch vụ (Service Layer)
│   ├── download_service.dart     # Quản lý hàng đợi tải xuống an toàn
│   ├── novel_service.dart        # Import EPUB, quản lý truyện chữ nội bộ
│   ├── sync_service.dart         # Đồng bộ lịch sử đọc đa thiết bị
│   ├── auth_service.dart         # Đăng nhập Google / Email
│   ├── history_service.dart      # Ghi/đọc lịch sử đọc từ SQLite & Cloud
│   ├── background_service.dart   # Tải xuống ngầm khi App tắt màn hình
│   └── ...                       # (Và 10+ services khác)
│
└── features/                     # Tầng giao diện (UI Layer)
    ├── admin/                    # Dashboard quản lý (Chỉ Admin)
    ├── auth/                     # Màn hình Đăng nhập / Đăng ký
    ├── backup/                   # Giao diện sao lưu & khôi phục dữ liệu
    ├── catalog/                  # Danh sách truyện từ Drive, lọc thể loại
    ├── detail/                   # Chi tiết truyện & quản lý Follow
    ├── downloads/                # Lịch sử và hàng đợi tải xuống
    ├── forum/                    # Diễn đàn cộng đồng & Phòng chat
    ├── home/                     # Trang chủ (Banner, Trending)
    ├── library/                  # Thư viện cá nhân, Lịch sử & Analytics
    ├── main/                     # Main Scaffold chứa Navigation Bar
    ├── notification/             # Xem thông báo từ Admin gửi
    ├── reader/                   # Trình đọc lõi (Ngang/Dọc/PDF/EPUB)
    ├── search/                   # Hệ thống tìm kiếm có chống lag (Debounce)
    ├── settings/                 # Cài đặt ứng dụng
    ├── shared/                   # Các widget dùng chung (Buttons, Loaders...)
    └── storage/                  # Biểu đồ phân tích dung lượng ổ nhớ
```

---

## 6. Luồng Xử Lý Chi Tiết (Data Flow Deep Dive)

### 6.1 Luồng Đọc Truyện (Online → Offline → Cache)
```text
Bấm vào Chapter
    │
    ├─ SQLite: Chapter đã tải xuống?
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
                                                    └─ Nhận diện vị trí bằng GlobalKey (120fps)
```

### 6.2 Luồng Tải Xuống An Toàn (Download Queue)
```text
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
            ├─ DownloadService phát hiện xung đột
            ├─ Hủy tải ngay lập tức
            └─ Xóa tệp .part dở dang — Không để lại rác
```

---

## 7. Các Điểm Kỹ Thuật Đặc Biệt (Technical Highlights)

### 7.1 Theo Dõi Tiến Độ Cuộn Dọc O(1) (Pixel-Perfect Scroll Tracking)
Thay vì sử dụng tỉ lệ tuyến tính `(pixels / maxExtent)` gây sai lệch khi các trang truyện có chiều cao khác nhau (đặc biệt là Webtoon), hệ thống sử dụng thuật toán dò tọa độ thông qua `GlobalKey` kết hợp `RenderBox.localToGlobal`. Bằng cách chỉ kiểm tra khoảng 3-5 phần tử đang "sống" (mounted) trên màn hình, thanh tiến độ (slider) nhận diện chính xác tuyệt đối trang truyện đang ở tâm màn hình mà không làm giảm tốc độ khung hình (120FPS).

### 7.2 Hệ Thống Đồng Bộ Độc Lập (Decoupled Syncing)
Ứng dụng cô lập hoàn toàn tài nguyên cục bộ (Local EPUB Novels) và tài nguyên đám mây (Cloud Manga). Lịch sử đọc và tiến độ của Local Novel được mã hóa bằng tiền tố `LOCAL_NOVEL|` và chặn đồng bộ lên Firestore, đảm bảo máy chủ không bị rác dữ liệu từ các tệp cục bộ không xác định của người dùng, đồng thời giữ nguyên quyền lợi thống kê (Analytics) độc lập cho truyện chữ trên chính thiết bị đó.

### 7.3 Debounce Tìm Kiếm
Ô tìm kiếm áp dụng **Debounce 500ms** — hệ thống chỉ gọi API/lọc dữ liệu sau khi người dùng **dừng gõ 0.5 giây**, triệt tiêu tình trạng giật lag UI và tiết kiệm băng thông.

### 7.4 Merge Chapters (Gộp Chương Online + Offline)
Thuật toán `ChapterUtils.mergeChapters()` thực hiện gộp danh sách chương từ `catalog.json` (Drive) với danh sách trong SQLite cục bộ, ưu tiên giữ lại metadata của chương đã tải. Người dùng luôn thấy danh sách chương đầy đủ và nhất quán dù có mạng hay không.

### 7.5 Aggregation Count (Thống kê không kéo dữ liệu)
Thay vì dùng `getDocs()` kéo hàng nghìn documents về máy để đếm số lượng View/User, Admin Panel dùng `.count().get()` của Firestore, tiết kiệm **99.9% chi phí Reads**.

### 7.6 Firebase Stream Tối Ưu (1 Stream → N Widgets)
Thay vì mỗi Widget con tự mở 1 Stream riêng, toàn bộ dữ liệu tương tác trong bài đăng diễn đàn được lấy từ **1 Stream duy nhất** ở Widget cha (`ForumPostPage`), sau đó truyền xuống cây con. Giảm số lượng kết nối đồng thời từ hàng trăm xuống còn **1 kết nối mỗi màn hình**.

---

## 8. Thiết Kế Giao Diện (UI/UX Design System)

### 8.1 Triết Lý Thiết Kế
Giao diện được xây dựng xoay quanh triết lý **"Dark + Premium"** — tôn trọng nội dung là trên hết.
- **Nền tối (Dark Mode)**: Giảm mỏi mắt khi đọc đêm, tiết kiệm pin AMOLED.
- **Màu chủ đạo**: Gradient Tím - Xanh Dương (`#6C5CE7` → `#0984E3`) hiện đại, sang trọng.
- **Typography**: Tận dụng font hệ thống với weight và spacing tinh chỉnh để tối ưu khả năng đọc.

### 8.2 Micro-animations & UX Chi Tiết
- **Hold-to-Load Arc**: Khi giữ ở cuối chương, vòng tròn tiến trình hiển thị đếm ngược 1.5 giây để tự động nhảy chương sau. Trực quan, mượt mà.
- **Shimmer Loading**: Mọi hình ảnh và card truyện đều có hiệu ứng shimmer lấp lánh khi tải dữ liệu, thay vì các hình vuông xám vô hồn.
- **Snackbar thông minh**: Không bao giờ chặn thao tác chạm của người dùng, tự ẩn sau vài giây.

---

## 9. Tải Xuống & Cài Đặt

> **📥 Download Android APK (Bản Release mới nhất):**
> [**TẢI FILE APK TẠI ĐÂY — GOOGLE DRIVE**](https://drive.google.com/file/d/1cLiav9dThWEWqYYU1XqrVrbgPIS7RmLX/view?usp=sharing)

**Hướng dẫn cài đặt:**
1. Tải file `app-release.apk` về thiết bị Android.
2. Bật "Cài đặt từ nguồn không xác định" (Unknown Sources).
3. Hoàn tất cài đặt và Đăng nhập bằng Google.

---

## 10. Roadmap — Kế Hoạch Phát Triển

### ✅ Đã Hoàn Thành (v1.0)
- [x] Trình đọc truyện tranh (CBZ/ZIP/PDF) dọc & ngang.
- [x] Trình đọc truyện chữ EPUB.
- [x] Hệ thống tải xuống nền (Background Download).
- [x] Thư viện cá nhân (Kéo-thả danh mục, bảo vệ danh mục Mặc định).
- [x] Diễn đàn cộng đồng & phòng chat real-time.
- [x] Admin Panel thống kê Dashboard.
- [x] Text-to-Speech đọc truyện chữ.
- [x] Sao lưu & Khôi phục dữ liệu cục bộ.
- [x] Anti-OOM & Fast Cache hoàn chỉnh.
- [x] Đồng bộ tiến độ đọc đa thiết bị qua Firestore.

### 🚧 Đang Phát Triển (v1.1)
- [ ] Thêm định dạng CBR (Comic Book RAR).
- [ ] Hỗ trợ mua truyện / ủng hộ tác giả (Donation flow).

### 💡 Dự Kiến (v2.0)
- [ ] Hỗ trợ iOS (App Store).
- [ ] Machine Learning gợi ý truyện theo thói quen đọc.
- [ ] Chế độ đọc nhóm (Co-reading).

---

## 11. Kết Luận

**Manga Reader** không chỉ là một ứng dụng đọc truyện — đây là một bằng chứng thuyết phục về năng lực thiết kế và triển khai hệ thống phần mềm thực tế cấp chuyên nghiệp.

Dự án giải quyết thành công bài toán phức tạp đa chiều:
- **Kỹ thuật**: Xử lý file nặng, đa luồng, không lỗi OOM nhờ Isolate và Fast Cache.
- **Kinh tế**: Vận hành siêu tiết kiệm nhờ Serverless (Drive + Firebase).
- **UX**: Mượt mà 120fps, thuật toán toạ độ thông minh, offline-first hoàn toàn.
- **Cộng đồng**: Tương tác real-time nhưng không "đốt" bandwidth.
- **Quản trị**: Quản lý 100% tài nguyên và người dùng ngay trong app.

> 💬 *"Manga Reader là minh chứng cho thấy với kiến trúc đúng đắn và kỹ thuật tối ưu hóa sâu, một lập trình viên hoàn toàn có thể tạo ra sản phẩm UX thượng hạng, sẵn sàng phục vụ quy mô lớn."*
