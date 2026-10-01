import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/features/detail/widgets/manga_description_section.dart';

void main() {
  testWidgets('MangaDescriptionSection shows placeholder when empty', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MangaDescriptionSection(description: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Giới Thiệu'), findsOneWidget);
    expect(find.text('Chưa có phần giới thiệu cho bộ truyện này.'), findsOneWidget);
    expect(find.text('Xem thêm...'), findsNothing);
  });

  testWidgets('Short description (fits within 4 lines) does not show Xem them button', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: MangaDescriptionSection(description: 'Một câu chuyện ngắn gọn chỉ có 1 dòng duy nhất.'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Một câu chuyện ngắn gọn chỉ có 1 dòng duy nhất.'), findsOneWidget);
    expect(find.text('Xem thêm...'), findsNothing);
    expect(find.text('Rút gọn'), findsNothing);
  });

  testWidgets('Long description exceeding 4 lines displays Xem them, expands and collapses, and resets on description change', (tester) async {
    const longText = 'Dòng 1: Khởi đầu câu chuyện huyền ảo.\n'
        'Dòng 2: Nhân vật chính bước vào thế giới mới với sức mạnh tiềm ẩn.\n'
        'Dòng 3: Những kẻ thù nguy hiểm bắt đầu xuất hiện và đe dọa vương quốc.\n'
        'Dòng 4: Một trận chiến hoành tráng nổ ra tại thung lũng bí ẩn.\n'
        'Dòng 5: Sự thật về thân thế của người anh hùng dần được hé lộ.\n'
        'Dòng 6: Cuộc hành trình tiếp diễn với những thử thách cam go hơn.';

    var currentDesc = longText;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                child: Column(
                  children: [
                    MangaDescriptionSection(description: currentDesc),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          currentDesc = 'Truyện mới ngắn gọn.';
                        });
                      },
                      child: const Text('Đổi truyện'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    // Verify 'Xem thêm...' is rendered
    expect(find.text('Xem thêm...'), findsOneWidget);

    // Tap on 'Xem thêm...' to expand
    await tester.tap(find.text('Xem thêm...'));
    await tester.pumpAndSettle();

    // Verify it is expanded and button says 'Rút gọn'
    expect(find.text('Rút gọn'), findsOneWidget);

    // Tap on 'Rút gọn' to collapse back
    await tester.tap(find.text('Rút gọn'));
    await tester.pumpAndSettle();

    // Verify it is collapsed and shows 'Xem thêm...' again
    expect(find.text('Xem thêm...'), findsOneWidget);
    expect(find.text('Rút gọn'), findsNothing);

    // Expand again before switching description to test reset from expanded state
    await tester.tap(find.text('Xem thêm...'));
    await tester.pumpAndSettle();
    expect(find.text('Rút gọn'), findsOneWidget);

    // Tap on 'Đổi truyện' to change widget.description
    await tester.tap(find.text('Đổi truyện'));
    await tester.pumpAndSettle();

    // Verify it reset: short text has no 'Rút gọn' or 'Xem thêm...'
    expect(find.text('Truyện mới ngắn gọn.'), findsOneWidget);
    expect(find.text('Rút gọn'), findsNothing);
    expect(find.text('Xem thêm...'), findsNothing);
  });

  testWidgets('MangaDescriptionSection shows placeholder when whitespace-only', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MangaDescriptionSection(description: '   \n  \t  '),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Giới Thiệu'), findsOneWidget);
    expect(find.text('Chưa có phần giới thiệu cho bộ truyện này.'), findsOneWidget);
    expect(find.text('Xem thêm...'), findsNothing);
  });

  testWidgets('Respects MediaQuery textScaler when calculating line overflow', (tester) async {
    const borderlineText = 'Dòng 1 ngắn.\n'
        'Dòng 2 vừa phải một chút.\n'
        'Dòng 3 kết thúc.';

    // With 1.0 scale factor in 400px width, 3 lines fit in 4 lines limit (no Xem thêm)
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: MangaDescriptionSection(description: borderlineText),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Xem thêm...'), findsNothing);

    // With 2.0 scale factor, font size doubles and 3 long lines now wrap into > 4 lines (shows Xem thêm)
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: SizedBox(
              width: 400,
              child: MangaDescriptionSection(description: borderlineText),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Xem thêm...'), findsOneWidget);
  });

  testWidgets('Safely handles unconstrained infinite width without layout errors', (tester) async {
    const multiLineText = 'Dòng 1\nDòng 2\nDòng 3\nDòng 4\nDòng 5\nDòng 6';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UnconstrainedBox(
            constrainedAxis: Axis.vertical,
            child: MangaDescriptionSection(description: multiLineText),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Xem thêm...'), findsOneWidget);
  });
}
