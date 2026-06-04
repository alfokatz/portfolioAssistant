/// Helpers defensivos para parsear datos de catalog items GenUI.
abstract final class GenUiHelpers {
  static String safeEnum(
    dynamic value,
    List<String> validValues, {
    required String defaultValue,
  }) {
    if (value is String && validValues.contains(value)) return value;
    return defaultValue;
  }

  static double safeDouble(dynamic value, {required double defaultValue}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  static int safeInt(dynamic value, {required int defaultValue}) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  static String safeString(dynamic value, {required String defaultValue}) {
    if (value is String) return value;
    if (value != null) return value.toString();
    return defaultValue;
  }

  static List<T> safeList<T>(
    dynamic value, {
    required List<T> defaultValue,
    T Function(dynamic item)? mapItem,
  }) {
    if (value is! List) return defaultValue;
    if (mapItem == null) return List<T>.from(value.whereType<T>());
    return value.map(mapItem).toList();
  }

  static bool safeBool(dynamic value, {required bool defaultValue}) {
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    return defaultValue;
  }

  static List<double> safeDoubleList(
    dynamic value, {
    List<double> defaultValue = const [],
  }) {
    if (value is! List) return defaultValue;
    return value
        .map((e) => safeDouble(e, defaultValue: 0))
        .toList();
  }

  static List<String> safeStringList(
    dynamic value, {
    List<String> defaultValue = const [],
  }) {
    if (value is! List) return defaultValue;
    return value.map((e) => safeString(e, defaultValue: '')).toList();
  }
}
