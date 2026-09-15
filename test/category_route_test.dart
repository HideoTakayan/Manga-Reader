import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:manga_reader/core/app_router.dart';

class _MockAuthPlatform extends FirebaseAuthPlatform {
  _MockAuthPlatform(FirebaseApp app) : super(appInstance: app);

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) {
    return _MockAuthPlatform(app);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = _MockAuthPlatform(Firebase.app());
  });

  test('appRouter registers rootNavigatorKey and top-level category routes', () {
    expect(rootNavigatorKey, isNotNull);
    expect(appRouter.configuration.navigatorKey, equals(rootNavigatorKey));

    final routes = appRouter.configuration.routes;
    final categoryRoutes = routes.whereType<GoRoute>().where(
      (r) => r.path == '/settings/categories' || r.path == '/categories',
    ).toList();

    expect(categoryRoutes.length, equals(2));
    for (final route in categoryRoutes) {
      expect(route.parentNavigatorKey, equals(rootNavigatorKey));
    }
  });
}
