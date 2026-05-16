import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = _SignedOutAuthPlatform(Firebase.app());
  });

  testWidgets('App smoke test', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MangaApp()));
    await tester.pump();

    expect(find.byType(MangaApp), findsOneWidget);
  });
}

class _SignedOutAuthPlatform extends FirebaseAuthPlatform {
  _SignedOutAuthPlatform(FirebaseApp app) : super(appInstance: app);

  UserPlatform? _currentUser;

  @override
  UserPlatform? get currentUser => _currentUser;

  @override
  set currentUser(UserPlatform? userPlatform) {
    _currentUser = userPlatform;
  }

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) {
    return _SignedOutAuthPlatform(app);
  }

  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) {
    return this;
  }

  @override
  Stream<UserPlatform?> authStateChanges() {
    return Stream<UserPlatform?>.value(null);
  }
}
