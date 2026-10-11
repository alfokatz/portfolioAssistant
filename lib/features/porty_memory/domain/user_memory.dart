/// Un dato que Porty sabe del usuario ("quiere comprarse una MacBook Neo
/// rosa", "ahorra 200 USD por mes"). Lo anota Porty en el chat (tool
/// `remember_about_user`) o el usuario desde Ajustes, y viaja en el
/// contexto de cada turno para personalizar las respuestas.
class UserMemory {
  const UserMemory({
    required this.id,
    required this.content,
    required this.category,
    required this.source,
    required this.updatedAt,
  });

  /// Lo mismo que el `check` de la tabla.
  static const maxLength = 280;

  /// Tope por usuario (lo hace cumplir un trigger).
  static const maxPerUser = 60;

  final String id;
  final String content;
  final UserMemoryCategory category;
  final UserMemorySource source;
  final DateTime updatedAt;

  static UserMemory? fromRow(Map<String, dynamic> row) {
    final id = row['id'] as String?;
    final content = (row['content'] as String?)?.trim();
    final updatedAt = DateTime.tryParse('${row['updated_at']}');
    if (id == null || content == null || content.isEmpty || updatedAt == null) {
      return null;
    }
    return UserMemory(
      id: id,
      content: content,
      category:
          UserMemoryCategory.fromStorage(row['category'] as String?) ??
          UserMemoryCategory.other,
      source:
          row['source'] == UserMemorySource.user.storageValue
              ? UserMemorySource.user
              : UserMemorySource.porty,
      updatedAt: updatedAt,
    );
  }
}

/// De qué se trata el dato: agrupa la pantalla de memoria y le dice al
/// modelo cuándo usarlo.
enum UserMemoryCategory {
  /// Metas y cosas que quiere comprar o lograr.
  goal('goal'),

  /// Ingresos, capacidad de ahorro, deudas, ahorros fuera de la app.
  finances('finances'),

  /// Situación de vida: estudia, trabaja, hijos, edad, país.
  life('life'),

  /// Gustos al invertir: "prefiero ETFs", "no quiero tabacaleras".
  preference('preference'),
  other('other');

  const UserMemoryCategory(this.storageValue);
  final String storageValue;

  static UserMemoryCategory? fromStorage(String? value) =>
      values.where((v) => v.storageValue == value).firstOrNull;
}

enum UserMemorySource {
  porty('porty'),
  user('user');

  const UserMemorySource(this.storageValue);
  final String storageValue;
}

sealed class UserMemoryFailure implements Exception {
  const UserMemoryFailure();
}

class UserMemoryLimitReached extends UserMemoryFailure {
  const UserMemoryLimitReached();
}

class UserMemoryUnavailable extends UserMemoryFailure {
  const UserMemoryUnavailable();
}
