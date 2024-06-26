// ignore: dangling_library_doc_comments
/// CSRF Token Example
///
/// Add interceptors to handle CSRF token.
/// - token update
/// - retry policy
///
/// Scenario:
/// 1. Client access to the Server by using `GET` method.
/// 2. Server generates CSRF token and sends it to the client.
/// 3. Client make a request to the Server by using `POST` method with the CSRF token.
/// 4. If the CSRF token is invalid, the Server returns 401 status code.
/// 5. Client requests a new CSRF token and retries the request.
import 'dart:developer';

import 'package:dio/dio.dart';

void main() async {
  /// HTML example:
  /// ``` html
  /// <input type="hidden" name="XSRF_TOKEN" value=${cachedCSRFToken} />
  /// ```
  const String cookieKey = 'XSRF_TOKEN';

  /// Header key for CSRF token
  const String headerKey = 'X-Csrf-Token';

  String? cachedCSRFToken;

  void printLog(
    int index,
    String path,
  ) =>
      log(
        '''
#$index
- Path: '$path'
- CSRF Token: $cachedCSRFToken
''',
        name: 'queued_interceptor_csrftoken.dart',
      );

  final dio = Dio()
    ..options.baseUrl = 'https://httpbun.com/'
    ..interceptors.addAll(
      [
        /// Handles CSRF token
        QueuedInterceptorsWrapper(
          /// Adds CSRF token to headers, if it exists
          onRequest: (requestOptions, handler) {
            if (cachedCSRFToken != null) {
              requestOptions.headers[headerKey] = cachedCSRFToken;
              requestOptions.headers['Set-Cookie'] =
                  '$cookieKey=$cachedCSRFToken';
            }
            return handler.next(requestOptions);
          },

          /// Update CSRF token from [response] headers, if it exists
          onResponse: (response, handler) {
            final token = response.headers.value(headerKey);

            if (token != null) {
              cachedCSRFToken = token;
            }
            return handler.resolve(response);
          },

          onError: (error, handler) async {
            if (error.response == null) {
              return handler.next(error);
            }

            /// When request fails with 401 status code, request new CSRF token
            if (error.response?.statusCode == 401) {
              try {
                final tokenDio = Dio(
                  BaseOptions(baseUrl: error.requestOptions.baseUrl),
                );

                /// Generate CSRF token
                ///
                /// This is a MOCK REQUEST to generate a CSRF token.
                /// In a real-world scenario, this should be generated by the server.
                final result = await tokenDio.post(
                  '/response-headers',
                  queryParameters: {
                    headerKey: '94d6d1ca-fa06-468f-a25c-2f769d04c26c',
                  },
                );

                if (result.statusCode == null ||
                    result.statusCode! ~/ 100 != 2) {
                  throw DioException(requestOptions: result.requestOptions);
                }

                final updatedToken = result.headers.value(headerKey);
                if (updatedToken == null) {
                  throw ArgumentError.notNull(headerKey);
                }

                cachedCSRFToken = updatedToken;

                return handler.next(error);
              } on DioException catch (e) {
                return handler.reject(e);
              }
            }
          },
        ),

        /// Retry the request when 401 occurred
        QueuedInterceptorsWrapper(
          onError: (error, handler) async {
            if (error.response != null && error.response!.statusCode == 401) {
              final retryDio = Dio(
                BaseOptions(baseUrl: error.requestOptions.baseUrl),
              );

              if (error.requestOptions.headers.containsKey(headerKey) &&
                  error.requestOptions.headers[headerKey] != cachedCSRFToken) {
                error.requestOptions.headers[headerKey] = cachedCSRFToken;
              }

              /// In real-world scenario,
              /// the request should be requested with [error.requestOptions]
              /// using [fetch] method.
              /// ``` dart
              /// final result = await retryDio.fetch(error.requestOptions);
              /// ```
              final result = await retryDio.get('/mix/s=200');

              return handler.resolve(result);
            }
          },
        ),
      ],
    );

  /// Make Requests
  printLog(0, 'initial');

  /// #1 Access to the Server
  final accessResult = await dio.get(
    '/response-headers',

    /// Pretend the Server has generated CSRF token
    /// and passed it to the client.
    queryParameters: {
      headerKey: 'fbf07f2b-b957-4555-88a2-3d3e30e5fa64',
    },
  );
  printLog(1, accessResult.realUri.path);

  /// #2 Make a request(POST) to the Server
  ///
  /// Pretend the token has expired.
  ///
  /// Then the interceptor will request a new CSRF token
  final createResult = await dio.post(
    '/mix/s=401/',
  );
  printLog(2, createResult.realUri.path);
}
