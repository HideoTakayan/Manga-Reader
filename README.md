# Báo Cáo Phát Triển Ứng Dụng Đọc Truyện Tranh (Manga Reader)

## 1. Giới Thiệu Hệ Thống

**Manga Reader** là ứng dụng di động đa nền tảng (Android/iOS) được thiết kế để giải quyết bài toán đọc truyện tranh trực tuyến với trải nghiệm người dùng cao cấp (Premium UX), loại bỏ quảng cáo và sự phụ thuộc vào các server truyện lậu thiếu ổn định. Hệ thống áp dụng mô hình **Serverless**, tận dụng tối đa hệ sinh thái **Google Cloud** (Google Drive, Firebase) để vận hành với chi phí tối thiểu nhưng hiệu năng tối đa.

### 1.1 Mục Tiêu
- Xây dựng ứng dụng đọc truyện có giao diện hiện đại, hỗ trợ các thao tác vuốt chạm tự nhiên (Gestures).
- Thiết kế theo tư duy **Offline-First**: người dùng có thể tải chương về máy và đọc hoàn toàn không cần mạng Internet.
- Trao quyền kiểm soát dữ liệu cho người dùng: Ứng dụng hoạt động như một "trình đọc" (Viewer) cho kho dữ liệu trên Google Drive.
- Đồng bộ hóa lịch sử đọc và danh sách theo dõi (Follow) qua Firebase Firestore.
- Cung cấp công cụ quản trị nội dung trực tiếp trong app (Admin Panel) — không cần trang web riêng.

### 1.2 Lý Do Triển Khai
- **Giải quyết vấn đề lưu trữ chi phí thấp**: Thay vì host nội dung trên server riêng (chi phí cao), ứng dụng đọc trực tiếp từ Google Drive qua API, giúp chi phí vận hành gần như bằng 0.
- **Thách thức kỹ thuật**: Áp dụng kiến trúc Feature-First, State Management bằng Riverpod, cơ sở dữ liệu cục bộ SQLite và xử lý file nén CBZ/ZIP/PDF trực tiếp trên thiết bị.

---

## 2. Kiến Trúc Hệ Thống

Hệ thống được xây dựng theo mô hình **Client-Serverless** với kiến trúc **Feature-First**. App giao tiếp trực tiếp với các dịch vụ Google APIs mà không thông qua Backend trung gian.

### 2.1 Sơ Đồ Kiến Trúc Tổng Quan
```
[Người Dùng (Mobile App)]
        |
        +---> [Google Drive API v3] <---> [Kho Truyện (CBZ/ZIP/PDF + catalog.json)]
        |       (Lưu trữ nội dung)
        |
        +---> [Firebase Auth]
        |       (Xác thực Email/Password)
        |
        +---> [Cloud Firestore]
        |       (Lượt view, lượt thích, danh sách follow)
        |
        +---> [SQLite Local (comics.db)]
                (Lịch sử đọc, thư viện cá nhân, chapter đã tải)
```

### 2.2 Các Thành Phần Chính

#### 2.2.1 Mobile Application (Frontend)
- **Công nghệ**: Flutter (Dart), Riverpod (State Management), GoRouter (Navigation).
- **Chức năng**:
  - Render giao diện theo phong cách Modern Dark UI.
  - Xử lý logic tìm kiếm, lọc truyện theo thể loại (Genre).
  - **Core Reader Engine**: Module đọc truyện hỗ trợ chế độ dọc/ngang, Hold-to-Load chuyển chương, tự động lưu trang đang đọc.
  - **Offline Engine**: Giải nén file CBZ/ZIP bằng thư viện `archive`, render PDF bằng `pdfx`, đọc trực tiếp từ bộ nhớ máy.
  - **Local Database (SQLite)**: Lưu lịch sử đọc, thư viện cá nhân, thông tin chapter đã tải xuống.

#### 2.2.2 Google Drive (Content Storage)
- **Vai trò**: Đóng vai trò là CMS (Content Management System) và File Server.
- **Cấu trúc dữ liệu**:
  - `Root Folder` → `Tên Truyện` → `Chapter Folder` → `File nén (.cbz, .zip, .pdf)`.
  - Metadata truyện được lưu trong `catalog.json` tại thư mục gốc, tự động được Admin tạo/cập nhật qua app.

#### 2.2.3 Firebase Cloud (User Data)
- **Authentication**: Đăng nhập bằng Email/Password hoặc Google Account.
- **Firestore**: Lưu trữ lượt xem/lượt thích của từng Chapter và danh sách truyện đang theo dõi (Follow) của người dùng.

---

## 3. Luồng Xử Lý Dữ Liệu (Data Flow)

### 3.1 Luồng Xem Chi Tiết Truyện (Offline-First)
1. App kiểm tra SQLite cục bộ xem có dữ liệu truyện này chưa → **Hiển thị ngay lập tức** nếu có (0 giây chờ).
2. Song song, gọi Google Drive API lấy `catalog.json` mới nhất và Firebase lấy thống kê view/like.
3. Dùng thuật toán `ChapterUtils.mergeChapters()` gộp danh sách chương offline + online, loại bỏ trùng lặp, ưu tiên giữ chapter đã tải.
4. Cập nhật UI với dữ liệu mới nhất.

### 3.2 Luồng Đọc Truyện (Reader Engine)
1. Người dùng bấm vào Chapter → Router điều hướng đến `ReaderPage`.
2. `ReaderNotifier` (Riverpod) kiểm tra SQLite: Chapter đã tải về chưa?
   - **Có**: Giải nén CBZ/ZIP hoặc render PDF từ file cục bộ → Hiển thị ảnh.
   - **Không**: Tải file từ Google Drive API → Giải nén trong RAM → Hiển thị ảnh.
3. Cơ chế **Hold-to-Load**: Giữ cuộn 1.5 giây ở cuối/đầu chương → Tự động chuyển chương tiếp/trước.
4. `HistoryService` liên tục ghi trang đang đọc vào SQLite.
5. `InteractionService` tự động cộng lượt xem lên Firestore.

### 3.3 Luồng Tải Ngầm (Background Download)
1. Người dùng bấm "Tải xuống" → `DownloadService` nhận task.
2. `Wakelock` giữ CPU không ngủ, tải từng file xuống bộ nhớ điện thoại.
3. `NotificationService` bắn thông báo tiến độ ra ngoài màn hình khóa.
4. Sau khi hoàn tất, `DatabaseHelper` lưu đường dẫn file vào SQLite.

---

## 4. Kết Quả Đạt Được

Hệ thống đã hoàn thiện các module cốt lõi và chạy ổn định trên môi trường Android.

### 4.1 Tính Năng Nổi Bật
- **Bộ Lọc Tìm Kiếm Thông Minh**:
  - Hỗ trợ lọc theo tên truyện, tác giả và thể loại (Genre). Bấm vào thể loại trong trang chi tiết để lọc ngay.
- **Trải Nghiệm Đọc Liền Mạch**:
  - Đọc dọc hoặc ngang tùy chỉnh. Chuyển chương mượt mà bằng Hold-to-Load.
  - Tự động nhớ trang đọc dở, mở lại tiếp tục ngay.
- **Thư Viện Cá Nhân**:
  - Tạo thư mục, phân loại và kéo thả sắp xếp truyện theo sở thích. Dữ liệu lưu cục bộ.
- **Admin Panel trong App**:
  - Quản lý truyện (thêm/sửa/xóa), tải chapter mới lên, xem thống kê dashboard — toàn bộ ngay trong giao diện app.
- **Bảo Mật**: Các file cấu hình nhạy cảm (`service_account.json`, API keys) được tách biệt hoàn toàn khỏi source code public.

### 4.2 Triển Khai Thực Tế
- Đã build thành công file cài đặt `.apk`.
- Tốc độ load danh sách: < 1s (với cache SQLite).
- Tốc độ load ảnh: Phụ thuộc mạng, trung bình < 500ms/ảnh (online) / tức thì (offline).

---

## 5. Tải Xuống & Cài Đặt (Demo)

Dưới đây là link tải file APK bản build mới nhất để trải nghiệm thử:

> **📥 Download Android APK**: [**Tải File APK Tại Đây (Google Drive)**](https://drive.google.com/file/d/1wTTaZAyjQcpIFlepORbb43IpRl5lcVku/view?usp=drive_link)

*(Lưu ý: Đây là file debug/release nội bộ, vui lòng cho phép cài đặt từ nguồn không xác định nếu thiết bị yêu cầu)*

---

## 6. Kết Luận

Dự án Manga Reader đã chứng minh tính khả thi của việc xây dựng ứng dụng nội dung số phức tạp mà không cần đầu tư hạ tầng Server tốn kém. Bằng cách kết hợp linh hoạt Flutter, Google Drive API và Firebase, ứng dụng mang lại trải nghiệm mượt mà, chuyên nghiệp tương đương các app thương mại — với chi phí vận hành gần như bằng 0. Tư duy **Offline-First** và hệ thống Admin Panel tích hợp sẵn là điểm khác biệt lớn nhất so với các ứng dụng đọc truyện thông thường.