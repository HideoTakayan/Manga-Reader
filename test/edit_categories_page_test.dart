import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/features/library/edit_categories_page.dart';

void main() {
  testWidgets('EditCategoriesPage builds cleanly and renders categories list, cards, and FAB', (tester) async {
    final stream = Stream<List<String>>.value(['Mặc định', 'Truyện Đang Theo Dõi']);

    await tester.pumpWidget(
      MaterialApp(
        home: EditCategoriesPage(categoriesStream: stream),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Title & category count
    expect(find.text('Quản lý danh mục'), findsOneWidget);
    expect(find.text('2 danh mục'), findsOneWidget);

    // Verify categories rendered
    expect(find.text('Mặc định'), findsWidgets);
    expect(find.text('Truyện Đang Theo Dõi'), findsOneWidget);

    // Verify FAB
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Thêm danh mục'), findsOneWidget);

    // Verify Drag tip
    expect(find.textContaining('Kéo thả biểu tượng ☰'), findsOneWidget);

    // Verify lock chip for "Mặc định" and action buttons for custom category
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
  });

  testWidgets('Tapping FAB opens Add Category Dialog with input and buttons', (tester) async {
    final stream = Stream<List<String>>.value(['Mặc định']);

    await tester.pumpWidget(
      MaterialApp(
        home: EditCategoriesPage(categoriesStream: stream),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Tap on FAB
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Verify dialog appears
    expect(find.text('Thêm danh mục'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Hủy'), findsOneWidget);
    expect(find.text('Thêm'), findsOneWidget);

    // Test empty validation
    await tester.tap(find.text('Thêm'));
    await tester.pumpAndSettle();
    expect(find.text('Tên danh mục không được để trống'), findsOneWidget);

    // Close dialog
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Tapping delete button opens confirmation dialog', (tester) async {
    final stream = Stream<List<String>>.value(['Mặc định', 'Yêu thích']);

    await tester.pumpWidget(
      MaterialApp(
        home: EditCategoriesPage(categoriesStream: stream),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Tap delete button
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    // Verify confirmation dialog
    expect(find.text('Xóa danh mục?'), findsOneWidget);
    expect(find.textContaining('Tất cả truyện trong mục "Yêu thích" sẽ được gỡ khỏi danh mục này'), findsOneWidget);
    expect(find.text('Xóa'), findsOneWidget);

    // Dismiss
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(find.text('Xóa danh mục?'), findsNothing);
  });

  testWidgets('Tapping edit button opens Edit Category Dialog with validation and controller lifecycle', (tester) async {
    final stream = Stream<List<String>>.value(['Mặc định', 'Yêu thích']);

    await tester.pumpWidget(
      MaterialApp(
        home: EditCategoriesPage(categoriesStream: stream),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Tap edit button
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    // Verify dialog appears with current category name
    expect(find.text('Đổi tên danh mục'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Yêu thích'), findsWidgets);

    // Clear text and submit -> error validation
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Tên danh mục không được để trống'), findsOneWidget);

    // Enter existing name -> duplicate validation
    await tester.enterText(find.byType(TextField), 'Mặc định');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Danh mục "Mặc định" đã tồn tại'), findsOneWidget);

    // Cancel dialog
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(find.text('Đổi tên danh mục'), findsNothing);
  });
}

