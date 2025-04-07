import 'package:mynotes/services/auth/auth_provider.dart';
import 'package:mynotes/services/auth/auth_user.dart';

class AuthService implements AuthProvider {
  final AuthProvider authProvider;

  const AuthService(this.authProvider);
  @override
  Future<AuthUser> createUser({
    required String email,
    required String password,
  }) =>
      authProvider.createUser(email: email, password: password);

  @override
  AuthUser? get currentUser => authProvider.currentUser;

  @override
  Future<AuthUser> login({
    required String email,
    required String password,
  }) =>
      authProvider.login(
        email: email,
        password: password,
      );

  @override
  Future<void> logout() => authProvider.logout();

  @override
  Future<void> sendEmailVerification() => authProvider.sendEmailVerification();
}
