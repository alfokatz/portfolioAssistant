import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/statement_import/domain/import_row.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';

/// Error tipado de `statement-import` (`error.type`): `file_too_large`,
/// `unsupported_type`, `nothing_found`, `quota_exceeded`, `rate_limited`,
/// `unavailable`… `network` si no hubo respuesta.
class StatementImportException implements Exception {
  const StatementImportException(this.type);

  final String type;

  @override
  String toString() => 'StatementImportException($type)';
}

/// Manda el archivo a la edge function `statement-import`, que devuelve las
/// posiciones para la vista previa. No guarda nada en el servidor.
class StatementImportClient {
  StatementImportClient({PortyEdgeClient? client})
    : _client = client ?? PortyEdgeClient(dio: _createDio());

  final PortyEdgeClient _client;

  /// Igual que el servidor (2 MB).
  static const maxFileBytes = 2 * 1024 * 1024;

  /// Igual que el servidor.
  static const maxNoteChars = 2000;

  static Dio _createDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 30),
      // Leer un PDF con la IA puede tardar.
      receiveTimeout: const Duration(seconds: 90),
      validateStatus: (status) => status != null && status < 600,
    ),
  );

  Future<StatementReadResult> read({
    required String filename,
    required Uint8List bytes,
  }) async {
    if (bytes.length > maxFileBytes) {
      throw const StatementImportException('file_too_large');
    }
    final response = await _client.post('statement-import', {
      'filename': filename,
      'content_base64': base64Encode(bytes),
    });
    if (response.statusCode == 0) {
      throw const StatementImportException('network');
    }
    if (!response.ok) {
      throw StatementImportException(response.errorType ?? 'unavailable');
    }
    return StatementReadResult.fromJson(response.body!);
  }

  /// Lo que escribe el usuario en vez de un archivo (lo lee la IA).
  Future<StatementReadResult> readNote(String note) async {
    if (note.length > maxNoteChars) {
      throw const StatementImportException('note_too_long');
    }
    final response = await _client.post('statement-import', {'note': note});
    if (response.statusCode == 0) {
      throw const StatementImportException('network');
    }
    if (!response.ok) {
      throw StatementImportException(response.errorType ?? 'unavailable');
    }
    return StatementReadResult.fromJson(response.body!);
  }
}

final statementImportClientProvider = Provider<StatementImportClient>(
  (ref) => StatementImportClient(),
);
