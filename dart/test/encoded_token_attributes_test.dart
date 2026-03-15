import 'package:test/test.dart';
import 'package:vscode_textmate/vscode_textmate.dart';

void main() {
  void assertEquals(
    int metadata,
    int languageId,
    StandardTokenType tokenType,
    bool containsBalancedBrackets,
    int fontStyle,
    int foreground,
    int background,
  ) {
    final actual = {
      'languageId': EncodedTokenAttributes.getLanguageId(metadata),
      'tokenType': EncodedTokenAttributes.getTokenType(metadata),
      'containsBalancedBrackets':
          EncodedTokenAttributes.containsBalancedBrackets(metadata),
      'fontStyle': EncodedTokenAttributes.getFontStyle(metadata),
      'foreground': EncodedTokenAttributes.getForeground(metadata),
      'background': EncodedTokenAttributes.getBackground(metadata),
    };

    final expected = {
      'languageId': languageId,
      'tokenType': tokenType,
      'containsBalancedBrackets': containsBalancedBrackets,
      'fontStyle': fontStyle,
      'foreground': foreground,
      'background': background,
    };

    expect(actual, expected);
  }

  test('StackElementMetadata works', () {
    final value = EncodedTokenAttributes.set(
      0,
      1,
      OptionalStandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );
  });
}
