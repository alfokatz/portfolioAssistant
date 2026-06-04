import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/interceptors/header_interceptor.dart';
import 'package:portfolio_assistant/infraestructure/managers/environmet_manager_impl.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;

class HttpClient {
  Ref ref;
  final int _connectTimeOut = 60;
  final int _receiveTimeOut = 60;
  late Dio dio;

  HttpClient({
    required this.ref,
    required HeaderInterceptor headerInterceptor,
  }) {
    final options = BaseOptions(
      baseUrl: ref.read(environmentManager).getApiUrl(),
      connectTimeout: Duration(seconds: _connectTimeOut),
      receiveTimeout: Duration(seconds: _receiveTimeOut),
    );
    dio = Dio(options);
    dio.interceptors.add(headerInterceptor);
    if (!kReleaseMode) {
      dio.interceptors.add(
        LogInterceptor(requestBody: true, responseBody: true),
      );
    }
  }
}

final httpClientProvider = Provider(
  (ref) => HttpClient(
    ref: ref,
    headerInterceptor: ref.watch(headerInterceptorProvider),
  ),
);
