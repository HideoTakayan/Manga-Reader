# Code Review Sau Rollback

Ngày review: 2026-05-31

## Kết luận ngắn

Source Flutter hiện tại compile sạch và test hiện có đều pass. Tuy nhiên rollback đã đưa `firestore.rules` về phiên bản yếu hơn: cơ chế ban/mute forum không còn được enforce và một số counter có thể bị client sửa gian lận.

Thư mục `admin-web` đã bị xóa hoàn toàn. Báo cáo này chỉ review trạng thái app Flutter và cấu hình Firebase hiện còn trong repo.

## Finding 1 - High: user có thể tự sửa toàn bộ profile, bao gồm trạng thái ban

File: `firestore.rules`, dòng 36-40.

Rules hiện tại:

```rules
match /users/{userId} {
  allow read: if isOwner(userId) || isAdmin();
  allow create: if isOwner(userId);
  allow update: if isOwner(userId) || isAdmin();
  allow delete: if isAdmin();
}
```

Vì owner được update toàn bộ document, user có thể tự ghi hoặc xóa các field quản trị như:

- `isBanned`
- `mutedUntil`
- `mutedReason`

Hậu quả: nếu sau này admin ban user bằng cách ghi `isBanned: true`, user có thể tự gỡ ban từ client tùy chỉnh.

Khuyến nghị: chỉ cho owner update whitelist field profile an toàn; chỉ admin được update field moderation.

## Finding 2 - High: rollback làm mất toàn bộ enforcement ban/mute ở forum

File:

- `firestore.rules`, dòng 112-246.
- `lib/features/forum/forum_chat_page.dart`, dòng 18-190.
- `lib/features/admin/users_list_page.dart`, dòng 35-66.

Rules hiện tại chỉ kiểm tra `signedIn()` khi tạo bài, bình luận và tin nhắn. Không còn helper `isNotBanned()` hoặc kiểm tra `mutedUntil`.

UI chat cũng không đọc `users/{uid}.isBanned` hoặc `mutedUntil`, không hiện cảnh báo và không khóa composer.

Trang admin user hiện chỉ đọc `isBanned` để đổi màu và icon, chưa có thao tác ban/unban hoặc mute.

Hậu quả:

- Ban user hiện gần như chỉ là dữ liệu hiển thị.
- User bị ban vẫn có thể đăng bài, bình luận, like và gửi tin nhắn.
- Không còn chức năng cấm ngôn 24 giờ.

Khuyến nghị: khôi phục `isSafeProfileUpdate()`, `isNotBanned()` và kiểm tra moderation cho mọi write forum; bổ sung UX khóa composer.

## Finding 3 - High: counter manga và forum có thể bị client sửa sai

File:

- `firestore.rules`, dòng 17-33.
- `firestore.rules`, dòng 150-176.
- `firestore.rules`, dòng 201-212.
- `lib/services/interaction_service.dart`, dòng 12-73.
- `lib/features/forum/services/firebase_forum_repository.dart`, dòng 234-371.

### Manga stats

Rules manga chỉ giới hạn tên field thay đổi:

```rules
hasOnly(['viewCount', 'likeCount', 'ratingSum', 'ratingCount'])
```

Nhưng không giới hạn delta. Một client tùy chỉnh có thể ghi số âm hoặc số rất lớn.

### Forum stats

Forum giới hạn `+1/-1`, nhưng write counter không bị ràng buộc nguyên tử với document reaction/comment tương ứng. Client tùy chỉnh vẫn có thể gọi update counter nhiều lần.

`likeCount` của post và comment cũng chưa bị chặn xuống dưới `0`.

Hậu quả: bảng xếp hạng, lượt xem, lượt thích, rating và số comment có thể sai.

Khuyến nghị:

- Với quy mô nhỏ: chấp nhận đây là best-effort nhưng ghi rõ giới hạn.
- Nếu cần dữ liệu tin cậy: chuyển counter nhạy cảm sang Cloud Functions hoặc transaction backend.
- Ít nhất thêm kiểm tra non-negative và delta hợp lệ cho manga stats.

## Finding 4 - Medium: clone sạch từ GitHub không đủ file mẫu để build

File:

- `.gitignore`, dòng 72-74 và 90-94.
- `lib/main.dart`, dòng 7.
- `lib/data/drive_service.dart`, dòng 13.
- `lib/features/forum/services/image_upload_service.dart`, dòng 5.
- `lib/features/forum/services/tenor_service.dart`, dòng 3.

Các file local bắt buộc đang được ignore đúng cách:

- `lib/firebase_options.dart`
- `lib/config/drive_config.dart`
- `lib/config/cloudinary_config.dart`
- `lib/config/tenor_config.dart`
- `android/app/google-services.json`

Tuy nhiên repo chỉ có example cho Cloudinary và Tenor. Hiện thiếu:

- `lib/config/drive_config.dart.example`
- `lib/firebase_options.dart.example`
- Hướng dẫn setup config trong `README.md`

Hậu quả: máy hiện tại build được vì có file ignored local, nhưng clone sạch từ GitHub sẽ fail import.

Khuyến nghị: thêm template không chứa secret và bổ sung bước setup rõ ràng trong README.

## Finding 5 - Low: danh sách admin bị khai báo trùng

File:

- `lib/config/admin_config.dart`, dòng 6-9.
- `lib/features/admin/admin_dashboard_page.dart`, dòng 33-34.
- `firestore.rules`, dòng 13-15.

App đã có `AdminConfig`, nhưng `AdminDashboardPage` vẫn giữ `_adminEmails` riêng. Firestore rules cũng có danh sách riêng.

Hậu quả: thêm hoặc bỏ admin ở một nơi có thể quên cập nhật nơi khác.

Khuyến nghị: app Flutter chỉ dùng `AdminConfig`; về lâu dài ưu tiên custom claim `admin: true` thay cho email hardcode trong rules.

## Finding 6 - Low: artifact build Android đang bị track

File tracked:

```text
android/build/reports/problems/problems-report.html
```

Đây là output build, không nên commit. `.gitignore` hiện có rule cho `**/build/reports/`, nhưng file đã được track từ trước nên rule không loại bỏ được.

Khuyến nghị:

```bash
git rm --cached android/build/reports/problems/problems-report.html
```

## Kiểm tra đã chạy

```bash
flutter analyze
```

Kết quả:

```text
No issues found!
```

```bash
flutter test
```

Kết quả:

```text
All tests passed! (12 tests)
```

## File nhạy cảm

Các file config local nhạy cảm đang được `.gitignore` bảo vệ và không bị track:

```text
lib/config/drive_config.dart
lib/config/cloudinary_config.dart
lib/config/tenor_config.dart
lib/firebase_options.dart
android/app/google-services.json
```

Không phát hiện private key hoặc API key thật đang được track trong source.

## Thứ tự nên xử lý

1. Khôi phục rules profile whitelist và enforcement ban/mute forum.
2. Quyết định mức độ tin cậy cần có cho counter manga/forum.
3. Thêm config template để clone sạch build được.
4. Gỡ artifact build Android khỏi Git.

---

## 🤖 Phản hồi từ Trợ lý (Antigravity)

Em đã rà soát lại toàn bộ source code hiện tại dựa trên báo cáo của Codex. **Kết quả: Codex nói hoàn toàn chuẩn xác 100%.**

**Lý do:** Khi anh em mình code thêm tính năng **Admin Web**, chúng ta đã cùng nhau thắt chặt bảo mật rất nhiều ở phía `firestore.rules` (ví dụ như chặn người dùng tự sửa profile để gỡ ban, bắt buộc kiểm tra `isBanned` trước khi chat, v.v.). Tuy nhiên, do lệnh Rollback ban nãy đưa code về thẳng commit `e372e0d` (lúc đó mình chưa làm các tính năng bảo mật này), nên vô tình các lỗ hổng này lại bị mở ra như cũ.

**Đề xuất:**
Anh không cần phải lo lắng quá. Vì tính năng của Mobile App vẫn chạy bình thường. Nếu anh muốn, em có thể giúp anh thực hiện lại **Finding 1, 2 và 3** (viết lại rules bảo mật) trực tiếp vào code hiện tại để đảm bảo an toàn cho dữ liệu, mà không cần đụng gì tới Admin Web. Anh thấy sao ạ?
