import 'dart:io';
import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/managers/preferences_manager.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart'
    show preferenceManagerProvider;

enum HeaderField { authorization, contentType, accept, platform }

extension HeaderFieldExtension on HeaderField {
  String get key {
    switch (this) {
      case HeaderField.authorization:
        return 'Authorization';
      case HeaderField.contentType:
        return 'Content-Type';
      case HeaderField.accept:
        return 'Accept';
      case HeaderField.platform:
        return 'platform';
    }
  }
}

class HeaderInterceptor extends InterceptorsWrapper {
  final PreferencesManager _preferences;

  HeaderInterceptor(this._preferences);

  static const String _bearerPrefix = 'Bearer ';

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _preferences.getToken();

    final headers = <String, dynamic>{
      HeaderField.contentType.key: 'application/json',
      HeaderField.accept.key: 'application/json',
      HeaderField.platform.key: Platform.isIOS ? 'iOS' : 'Android',
    };

    if (token != null && token.isNotEmpty) {
      headers[HeaderField.authorization.key] = '$_bearerPrefix$token';
    }

    options.headers.addAll(headers);
    handler.next(options);
  }

  Map<String, dynamic> getHeaders({required String token}) {
    return {
      HeaderField.authorization.key: '$_bearerPrefix$token',
      HeaderField.contentType.key: 'application/json',
      HeaderField.platform.key: Platform.isIOS ? 'iOS' : 'Android',
    };
  }
}

final headerInterceptorProvider = Provider<HeaderInterceptor>(
  (ref) => HeaderInterceptor(ref.watch(preferenceManagerProvider)),
);
