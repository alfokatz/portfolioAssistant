/// Genera variantes de consulta para mejorar el match en Yahoo Search.
abstract final class SearchQueryVariants {
  static List<String> variants(String query) {
    final base = query.trim().toLowerCase();
    if (base.isEmpty) return const [];

    final seen = <String>{};
    final result = <String>[];

    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.length < 2 || !seen.add(trimmed)) return;
      result.add(trimmed);
    }

    add(base);
    add(base.replaceAll('takes two', 'take two'));
    add(_depluralizeWords(base));
    add(base.replaceAll(' ', '-'));
    add('$base stock');

    return result;
  }

  static String _depluralizeWords(String text) {
    return text
        .split(' ')
        .map((word) {
          if (word.length <= 3) return word;
          if (word.endsWith('ss')) return word;
          if (word.endsWith('es') && word.length > 4) {
            return word.substring(0, word.length - 2);
          }
          if (word.endsWith('s')) {
            return word.substring(0, word.length - 1);
          }
          return word;
        })
        .join(' ');
  }
}
