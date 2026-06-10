class ExploreNewsSource {
  const ExploreNewsSource({
    required this.title,
    required this.url,
    required this.snippet,
  });

  final String title;
  final String url;
  final String snippet;

  Map<String, String> toJson() => {
        'title': title,
        'url': url,
        'snippet': snippet,
      };
}

abstract final class ExploreNewsSourceParser {
  static final _urlPattern = RegExp(
    r'https?://[^\s<>\[\]()"]+',
    caseSensitive: false,
  );

  static const _titleFields = ['headline', 'title', 'titular'];
  static const _snippetFields = ['summary', 'snippet', 'resumen'];

  static List<ExploreNewsSource> parse(String rawText) {
    if (rawText.trim().isEmpty) return const [];

    final lines = rawText.split('\n');
    final sourcesSectionIndex = lines.indexWhere(
      (line) => line.trim().toLowerCase() == 'sources:',
    );
    final contentEnd = sourcesSectionIndex >= 0 ? sourcesSectionIndex : lines.length;
    final urlToSource = <String, ExploreNewsSource>{};

    for (var i = 0; i < contentEnd; i++) {
      for (final url in _extractUrlsFromLine(lines[i])) {
        urlToSource.putIfAbsent(
          url,
          () => ExploreNewsSource(
            title: _extractTitle(lines, i),
            url: url,
            snippet: _extractSnippet(lines, i),
          ),
        );
      }
    }

    if (sourcesSectionIndex >= 0) {
      for (var i = sourcesSectionIndex + 1; i < lines.length; i++) {
        for (final url in _extractUrlsFromLine(lines[i])) {
          urlToSource.putIfAbsent(
            url,
            () => ExploreNewsSource(
              title: _titleFromUrl(url),
              url: url,
              snippet: '',
            ),
          );
        }
      }
    }

    return urlToSource.values.toList(growable: false);
  }

  static Iterable<String> _extractUrlsFromLine(String line) sync* {
    for (final match in _urlPattern.allMatches(line)) {
      final url = _normalizeUrl(match.group(0)!);
      if (_isValidHttpUrl(url)) yield url;
    }
  }

  static String _normalizeUrl(String raw) {
    var url = raw.trim();
    while (url.isNotEmpty && '.,;:)]'.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static bool _isValidHttpUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static String _extractTitle(List<String> lines, int urlLineIndex) {
    final blockStart = _findBlockStart(lines, urlLineIndex);
    final blockEnd = _findBlockEnd(lines, urlLineIndex);

    for (var i = blockStart; i < blockEnd; i++) {
      final value = _extractField(lines[i], _titleFields);
      if (value.isNotEmpty) return value;
    }

    return _titleFromUrl(_firstUrlOnLine(lines[urlLineIndex]) ?? '');
  }

  static String _extractSnippet(List<String> lines, int urlLineIndex) {
    final blockStart = _findBlockStart(lines, urlLineIndex);
    final blockEnd = _findBlockEnd(lines, urlLineIndex);
    final snippets = <String>[];

    for (var i = blockStart; i < blockEnd; i++) {
      final value = _extractField(lines[i], _snippetFields);
      if (value.isNotEmpty) {
        snippets.add(value);
        continue;
      }

      if (i <= urlLineIndex) continue;

      final line = lines[i].trim();
      if (line.isEmpty || _lineHasUrl(line) || _looksLikeMetadataLine(line)) {
        continue;
      }

      final cleaned = line.replaceFirst(RegExp(r'^[-*]\s*'), '');
      if (cleaned.isNotEmpty) snippets.add(cleaned);
    }

    return snippets.join(' ').trim();
  }

  static String _extractField(String line, List<String> fieldNames) {
    final trimmed = line.trim();
    for (final field in fieldNames) {
      final pattern = RegExp(
        '^[-*]?\\s*${RegExp.escape(field)}\\s*[:\\-]\\s*(.+)\$',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(trimmed);
      if (match != null) return match.group(1)!.trim();
    }
    return '';
  }

  static int _findBlockStart(List<String> lines, int index) {
    for (var i = index; i >= 0; i--) {
      if (i < index && lines[i].trim().isEmpty) return i + 1;
      if (i < index && _looksLikeStoryHeader(lines[i])) return i;
    }
    return 0;
  }

  static int _findBlockEnd(List<String> lines, int index) {
    for (var i = index + 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) return i;
      if (_looksLikeStoryHeader(lines[i])) return i;
    }
    return lines.length;
  }

  static bool _looksLikeStoryHeader(String line) {
    final trimmed = line.trim();
    return RegExp(r'^story\s+\d+\s*:?\$', caseSensitive: false)
        .hasMatch(trimmed);
  }

  static bool _looksLikeMetadataLine(String line) {
    final trimmed = line.trim().toLowerCase();
    return trimmed.startsWith('- source') ||
        trimmed.startsWith('- publishedat') ||
        trimmed.startsWith('- affected tickers') ||
        trimmed.startsWith('- url') ||
        trimmed.startsWith('- headline') ||
        trimmed.startsWith('- title');
  }

  static bool _lineHasUrl(String line) => _urlPattern.hasMatch(line);

  static String? _firstUrlOnLine(String line) {
    final match = _urlPattern.firstMatch(line);
    if (match == null) return null;
    final url = _normalizeUrl(match.group(0)!);
    return _isValidHttpUrl(url) ? url : null;
  }

  static String _titleFromUrl(String url) {
    if (url.isEmpty) return '';

    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;

    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
    if (segments.isEmpty) return uri.host;

    return segments.last.replaceAll('-', ' ').replaceAll('_', ' ');
  }
}
