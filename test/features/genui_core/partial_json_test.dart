import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/genui_core/utils/partial_json.dart';

void main() {
  group('PartialJson.values', () {
    test('complete values, ignoring fences and loose text', () {
      expect(PartialJson.values('```json\n{"a":1}\n{"b":[2]}\n```'), [
        {'a': 1},
        {
          'b': [2],
        },
      ]);
    });

    test('an open string is closed where it is', () {
      expect(PartialJson.values('{"a":{"text":"Hola, ¿cómo e'), [
        {
          'a': {'text': 'Hola, ¿cómo e'},
        },
      ]);
    });

    test(
      'a key without value, a cut number or a trailing comma are dropped',
      () {
        expect(PartialJson.values('{"a":"x","b"'), [
          {'a': 'x'},
        ]);
        expect(PartialJson.values('{"a":"x","n":12'), [
          {'a': 'x'},
        ]);
        expect(PartialJson.values('{"list":[{"a":1},'), [
          {
            'list': [
              {'a': 1},
            ],
          },
        ]);
      },
    );

    test('a half escape is left out; escaped quotes and slashes are kept', () {
      expect(PartialJson.values(r'{"t":"dijo \"hola\" y \'), [
        {'t': 'dijo "hola" y '},
      ]);
      expect(PartialJson.values(r'{"t":"a\\'), [
        {'t': r'a\'},
      ]);
      expect(PartialJson.values(r'{"t":"caf\u00'), [
        {'t': 'caf'},
      ]);
    });

    test('braces inside strings do not count', () {
      expect(PartialJson.values('{"t":"a } ] {"}{"u":"b'), [
        {'t': 'a } ] {'},
        {'u': 'b'},
      ]);
    });

    test('nothing usable → empty', () {
      expect(PartialJson.values(''), isEmpty);
      expect(PartialJson.values('texto sin json'), isEmpty);
    });
  });
}
