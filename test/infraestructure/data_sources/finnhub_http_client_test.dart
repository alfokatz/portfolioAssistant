import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/finnhub_http_client.dart';

void main() {
  test('asks the finnhub proxy with the user JWT and never sends a token', () async {
    late RequestOptions sent;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sent = options;
            handler.resolve(Response(requestOptions: options, statusCode: 200, data: const {}));
          },
        ),
      );
    final client = FinnhubHttpClient(
      dio: dio,
      baseUrl: 'https://proj.supabase.co/functions/v1/finnhub',
      accessToken: () async => 'user-jwt',
      anonKey: 'anon',
    );

    await client.get('/stock/profile2', queryParameters: {'symbol': 'AAPL'});

    expect(sent.uri.toString(), 'https://proj.supabase.co/functions/v1/finnhub/stock/profile2?symbol=AAPL');
    expect(sent.uri.queryParameters.containsKey('token'), isFalse);
    expect(sent.headers['Authorization'], 'Bearer user-jwt');
    expect(sent.headers['apikey'], 'anon');
  });
}
