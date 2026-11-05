import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:songies/account/account_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('auth errors map by code', () {
    AccountError m(Object e) => accountErrorOf(e);
    expect(
      m(
        const AuthApiException(
          'x',
          statusCode: '400',
          code: 'invalid_credentials',
        ),
      ),
      AccountError.wrongCredentials,
    );
    expect(
      m(
        const AuthApiException(
          'x',
          statusCode: '400',
          code: 'email_not_confirmed',
        ),
      ),
      AccountError.emailNotConfirmed,
    );
    expect(
      m(const AuthApiException('x', statusCode: '403', code: 'otp_expired')),
      AccountError.badCode,
    );
    expect(
      m(
        const AuthApiException(
          'x',
          statusCode: '422',
          code: 'user_already_exists',
        ),
      ),
      AccountError.emailTaken,
    );
    expect(
      m(const AuthApiException('x', statusCode: '422', code: 'email_exists')),
      AccountError.emailTaken,
    );
    expect(
      m(const AuthApiException('x', statusCode: '422', code: 'same_password')),
      AccountError.samePassword,
    );
    expect(
      m(
        AuthWeakPasswordException(message: 'x', statusCode: '422', reasons: []),
      ),
      AccountError.weakPassword,
    );
    expect(
      m(
        const AuthApiException(
          'x',
          statusCode: '429',
          code: 'over_email_send_rate_limit',
        ),
      ),
      AccountError.tooManyRequests,
    );
    expect(
      m(
        const AuthApiException(
          'x',
          statusCode: '429',
          code: 'over_request_rate_limit',
        ),
      ),
      AccountError.tooManyRequests,
    );
    expect(
      m(const AuthApiException('x', statusCode: '429')),
      AccountError.tooManyRequests,
    );
    expect(
      m(
        const AuthApiException(
          'x',
          statusCode: '400',
          code: 'email_address_invalid',
        ),
      ),
      AccountError.invalidEmail,
    );
    expect(
      m(
        const AuthApiException(
          'x',
          statusCode: '422',
          code: 'validation_failed',
        ),
      ),
      AccountError.invalidEmail,
    );
    expect(
      m(
        const AuthApiException(
          'x',
          statusCode: '400',
          code: 'email_address_not_authorized',
        ),
      ),
      AccountError.emailNotAllowed,
    );
    expect(
      AccountError.invalidEmail.message,
      "That email address doesn't look right.",
    );
    expect(
      AccountError.emailNotAllowed.message,
      "The server can't send email to that address yet.",
    );
    // The sign-up trigger's unique violation reaches us as a 500.
    expect(
      m(
        AuthRetryableFetchException(
          message: 'Database error saving new user',
          statusCode: '500',
        ),
      ),
      AccountError.unknown,
    );
    expect(
      m(AuthRetryableFetchException(message: 'no network')),
      AccountError.offline,
    );
    expect(
      m(AuthRetryableFetchException(message: 'paused', statusCode: '503')),
      AccountError.offline,
    );
  });

  test('database, storage and network errors map', () {
    AccountError m(Object e) => accountErrorOf(e);
    expect(
      m(const PostgrestException(message: 'dup', code: '23505')),
      AccountError.usernameTaken,
    );
    expect(
      m(const PostgrestException(message: 'x', code: '42501')),
      AccountError.unknown,
    );
    expect(
      m(const StorageException('x', statusCode: '403')),
      AccountError.unknown,
    );
    expect(
      m(const StorageException('x', statusCode: 'ClientException')),
      AccountError.offline,
    );
    expect(m(const SocketException('down')), AccountError.offline);
    expect(m(http.ClientException('down')), AccountError.offline);
    expect(m(TimeoutException('slow')), AccountError.offline);
    expect(
      m(const AccountException(AccountError.badCode)),
      AccountError.badCode,
    );
    expect(m(StateError('?')), AccountError.unknown);
  });
}
