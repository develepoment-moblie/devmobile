import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/shared/services/app_exception.dart';
import 'package:nova_paris/user_management/services/user_repository.dart';

void main() {
  test('local account errors preserve actionable messages', () {
    expect(
      userError(
        const AppServiceException('E-mail ou mot de passe incorrect.', 401),
      ),
      'E-mail ou mot de passe incorrect.',
    );
    expect(
      userError(const AppServiceException('Action réservée au manager.', 403)),
      'Action réservée au manager.',
    );
  });

  test('unexpected local errors do not expose internal details', () {
    final message = userError(StateError('private database detail'));
    expect(message, contains('données locales'));
    expect(message, isNot(contains('private database detail')));
  });
}
