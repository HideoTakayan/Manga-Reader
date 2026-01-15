# Báo Cáo Phát Triển Ứng Dụng Đọc Truyện Tranh (Manga Reader)

## 1. Giới Thiệu Hệ Thống

**Manga Reader** là ứng dụng di động đa nền tảng (Android/iOS) được thiết kế để giải quyết bài toán đọc truyện tranh trực tuyến với trải nghiệm người dùng cao cấp (Premium UX), loại bỏ quảng cáo và sự phụ thuộc vào các server truyện lậu thiếu ổn định. Hệ thống áp dụng mô hình **Serverless**, tận dụng tối đa hệ sinh thái **Google Cloud** (Google Drive, Firebase) để vận hành với chi phí tối thiểu nhưng hiệu năng tối đa.

### 1.1 Mục Tiêu
- Xây dựng ứng dụng đọc truyện có giao diện hiện đại, hỗ trợ các thao tác vuốt chạm tự nhiên (Gestures).
- Tối ưu hóa tốc độ tải trang bằng cơ chế Pre-caching và quản lý ảnh thông minh.
- Trao quyền kiểm soát dữ liệu cho người dùng: Ứng dụng hoạt động như một "trình đọc" (Viewer) cho kho dữ liệu trên Google Drive cá nhân của họ.
- Đồng bộ hóa lịch sử đọc và danh sách yêu thích qua Firebase Realtime/Firestore.

### 1.2 Lý Do Triển Khai
- **Giải quyết vấn đề bản quyền & lưu trữ**: Thay vì host nội dung trên server riêng (rủi ro DMCA và chi phí cao), ứng dụng đọc trực tiếp từ Drive được cấp quyền.
- **Thách thức kỹ thuật**: Áp dụng kiến trúc Clean Architecture và các kỹ thuật xử lý ảnh phức tạp (Lazy loading, Smart Caching) trên nền tảng Flutter.

---

## 2. Kiến Trúc Hệ Thống

Hệ thống được xây dựng theo mô hình **Clean Architecture** kết hợp với kiến trúc **Client-Serverless**. App giao tiếp trực tiếp với các dịch vụ Google APIs mà không thông qua Backend trung gian.

### 2.1 Sơ Đồ Kiến Trúc Tổng Quan
```
[Người Dùng (Mobile App)]
        |
        +---> [Google Drive API v3] <---> [Kho Truyện (Images/JSON)]
        |       (Lưu trữ nội dung)
        |
        +---> [Firebase Auth]
        |       (Xác thực)
        |
        +---> [Cloud Firestore]
                (Đồng bộ Lịch sử/Yêu thích)
```

### 2.2 Các Thành Phần Chính

#### 2.2.1 Mobile Application (Frontend)
- **Công nghệ**: Flutter (Dart), Riverpod (State Management), GoRouter (Navigation).
- **Chức năng**:
  - Render giao diện người dùng theo phong cách Modern Dark UI.
  - Xử lý logic tìm kiếm, lọc truyện, hiển thị danh sách.
  - **Core Reader Engine**: Module hiển thị truyện hỗ trợ zoom, next/prev chapter thông minh, preload ảnh.
  - **Local Database**: SQFlite để lưu cache danh sách truyện offline.

#### 2.2.2 Google Drive (Content Storage)
- **Vai trò**: Đóng vai trò là CMS (Content Management System) và Image Server.
- **Cấu trúc dữ liệu**:
  - `Root Folder` -> `Tên Truyện` -> `Chapter Folder` -> `Files ảnh (.jpg, .png)`.
  - Metadata truyện được tự động trích xuất từ tên file hoặc file config đi kèm.

#### 2.2.3 Firebase Cloud (User Data)
- **Authentication**: Đăng nhập bằng Google Account.
- **Firestore**: Lưu trữ `ReadingHistory` (Người dùng đọc đến chap nào, trang mấy) và `Favorites` (Danh sách truyện theo dõi).

---

## 3. Luồng Xử Lý Dữ Liệu (Data Flow)

### 3.1 Luồng Khởi Động & Quét Dữ Liệu
1.  App khởi động, kiểm tra token đăng nhập Firebase & Google Drive.
2.  Background Service gọi Drive API `files.list` để quét thư mục truyện.
3.  Metadata (ID, Tên, Tác giả) được map vào SQLite local để hiển thị nhanh cho lần sau.

### 3.2 Luồng Đọc Truyện (Streaming)
1.  Người dùng chọn Chapter -> App gửi request lấy danh sách file ảnh trong folder Chapter đó.
2.  App hiển thị ảnh đầu tiên ngay lập tức.
3.  **Cơ chế Pre-fetch**: Trong khi người dùng xem trang 1, App âm thầm tải trang 2, 3 và lưu vào RAM Cache.
4.  Khi người dùng thực hiện thao tác **Hold-to-Load** (Giữ để chuyển chap), App gọi API lấy ID của folder chapter kế tiếp và lặp lại quy trình.

---

## 4. Kết Quả Đạt Được

Hệ thống đã hoàn thiện các module cốt lõi và chạy ổn định trên môi trường Android.

### 4.1 Tính Năng Nổi Bật
- **Bộ Lọc Tìm Kiếm Thông Minh**: 
  - Hỗ trợ lọc theo thể loại với 3 trạng thái: *Chọn* (v), *Loại trừ* (x), *Bỏ qua*. Giúp tìm kiếm chính xác truyện theo gu người đọc.
- **Trải Nghiệm Đọc Liền Mạch**: 
  - Không giật lag nhờ Image Caching `cached_network_image`.
  - Hiệu ứng chuyển cảnh mượt mà.
- **Bảo Mật**: Các file cấu hình nhạy cảm (`service_account`, `api_keys`) được tách biệt hoàn toàn khỏi source code.

### 4.2 Triển Khai Thực Tế
- Đã build thành công file cài đặt `.apk`.
- Tốc độ load danh sách: < 1s (với cache).
- Tốc độ load ảnh: Phụ thuộc mạng, trung bình < 500ms/ảnh.

---

## 5. Tải Xuống & Cài Đặt (Demo)

Dưới đây là link tải file APK bản build mới nhất để trải nghiệm thử:

> **📥 Download Android APK**: [**Tải File APK Tại Đây (Google Drive)**](https://drive.google.com/file/d/1wTTaZAyjQcpIFlepORbb43IpRl5lcVku/view?usp=drive_link)

*(Lưu ý: Đây là file debug/release nội bộ, vui lòng cho phép cài đặt từ nguồn không xác định nếu thiết bị yêu cầu)*

---

## 6. Kết Luận

Dự án Manga Reader đã chứng minh tính khả thi của việc xây dựng ứng dụng nội dung số phức tạp mà không cần đầu tư hạ tầng Server tốn kém. Bằng cách kết hợp linh hoạt Flutter và Google Cloud, ứng dụng mang lại trải nghiệm mượt mà, chuyên nghiệp tương đương các app thương mại. Trong giai đoạn tiếp theo, tôi sẽ tập trung vào tính năng **Offline Mode** và **Social Features** (Bình luận, đánh giá).