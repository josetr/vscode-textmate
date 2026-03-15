import 'package:test/test.dart';
import 'package:vscode_textmate/vscode_textmate.dart';

void main() {
  void isValid(String json) {
    final expected = parseJSON(json, null, false);
    final actual = parseJSON(json, null, false);
    expect(actual, expected);
  }

  void isInvalid(String json) {
    expect(() => parseJSON(json, null, false), throwsA(isA<Object>()));
  }

  test('JSON Invalid body', () {
    isInvalid('{}[]');
    isInvalid('*');
  });

  test('JSON Trailing Whitespace', () {
    isValid('{}\n\n');
  });

  test('JSON Objects', () {
    isValid('{}');
    isValid('{"key": "value"}');
    isValid(
      '{"key1": true, "key2": 3, "key3": [null], "key4": { "nested": {}}}',
    );
    isValid('{"constructor": true }');

    isInvalid('{');
    isInvalid('{3:3}');
    isInvalid("{'key': 3}");
    isInvalid('{"key" 3}');
    isInvalid('{"key":3 "key2": 4}');
    isInvalid('{"key":42, }');
    isInvalid('{"key:42');
  });
}
