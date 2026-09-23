import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../model/ecr_config.dart';
import 'ecr_web_service_message.dart';
import 'ecr_web_service_operation.dart';

/// POSTs signed JSON bodies to the Web Service ECR REST endpoints.
final class HttpEcrWebServiceApi {
  /// Uses [config] for Hub URLs and timeouts.
  HttpEcrWebServiceApi(this.config) : routes = EcrWebServiceRoutes(config);

  /// Till config (environment, timeouts, signing key).
  final EcrConfig config;

  /// Resolved Hub routes.
  final EcrWebServiceRoutes routes;

  HttpClient? _client;

  /// Aborts any in-flight HTTP exchange.
  void abort() {
    final HttpClient? client = _client;
    _client = null;
    client?.close(force: true);
  }

  /// POSTs [body] to [operation] and returns the decoded JSON object.
  Future<Map<String, Object?>> postJson(
    EcrWebServiceOperation operation,
    Map<String, Object?> body,
  ) async {
    final String payload = jsonEncode(body);
    final Uri url = Uri.parse(routes.fullUrl(operation));
    final HttpClient client = HttpClient();
    _client = client;
    client.connectionTimeout = config.connectTimeout;
    client.idleTimeout = config.responseTimeout;

    try {
      final HttpClientRequest request = await client
          .postUrl(url)
          .timeout(config.connectTimeout);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.add(utf8.encode(payload));

      final HttpClientResponse response = await request
          .close()
          .timeout(config.responseTimeout);
      final String text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(config.responseTimeout);

      if (text.trim().isEmpty) {
        return _errorBody(
          responseCode: response.statusCode.toString(),
          message:
              'Empty response from Web Service (${response.reasonPhrase})',
        );
      }

      final Object? decoded = jsonDecode(text);
      if (decoded is! Map) {
        return _errorBody(
          responseCode: response.statusCode.toString(),
          message: 'Response was not valid JSON',
        );
      }
      final Map<String, Object?> parsed = decoded.map(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>(key.toString(), value),
      );

      if (response.statusCode < 200 || response.statusCode > 299) {
        final String message = parsed['message']?.toString() ?? '';
        if (message.isNotEmpty || parsed['errorList'] is List) {
          return parsed;
        }
        return _errorBody(
          responseCode: response.statusCode.toString(),
          message: response.reasonPhrase.isEmpty
              ? 'HTTP ${response.statusCode}'
              : response.reasonPhrase,
        );
      }

      return parsed;
    } on TimeoutException {
      return _errorBody(
        responseCode: 'NO_RESPONSE',
        message: 'Web Service request timed out',
      );
    } on SocketException catch (error) {
      return _errorBody(
        responseCode: 'NO_RESPONSE',
        message: error.message.isEmpty
            ? 'Web Service request failed'
            : error.message,
      );
    } on HttpException catch (error) {
      return _errorBody(
        responseCode: 'NO_RESPONSE',
        message: error.message,
      );
    } on Object catch (error) {
      return _errorBody(
        responseCode: 'NO_RESPONSE',
        message: error.toString(),
      );
    } finally {
      if (identical(_client, client)) {
        _client = null;
      }
      client.close(force: true);
    }
  }

  Map<String, Object?> _errorBody({
    required String responseCode,
    required String message,
  }) =>
      <String, Object?>{
        'success': false,
        'responseCode': responseCode,
        'message': message,
      };
}
