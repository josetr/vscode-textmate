import 'theme.dart';

class FontAttribute {
  FontAttribute(this.fontFamily, this.fontSize, this.lineHeight);

  final String? fontFamily;
  final double? fontSize;
  final double? lineHeight;

  static final Map<String, FontAttribute> _map = <String, FontAttribute>{};

  static String _getKey(String? family, double? size, double? lineHeight) {
    return '$family|$size|$lineHeight';
  }

  static FontAttribute _get(String? family, double? size, double? lineHeight) {
    final key = _getKey(family, size, lineHeight);
    return _map.putIfAbsent(key, () => FontAttribute(family, size, lineHeight));
  }

  static FontAttribute from(String? family, double? size, double? lineHeight) {
    return _get(family, size, lineHeight);
  }

  FontAttribute withStyle(StyleAttributes? styleAttributes) {
    if (styleAttributes == null) {
      return this;
    }
    return _get(
      styleAttributes.fontFamily.isNotEmpty
          ? styleAttributes.fontFamily
          : fontFamily,
      styleAttributes.fontSize != 0 ? styleAttributes.fontSize : fontSize,
      styleAttributes.lineHeight != 0 ? styleAttributes.lineHeight : lineHeight,
    );
  }

  FontAttribute withTheme(StyleAttributes? styleAttributes) {
    return withStyle(styleAttributes);
  }
}

enum StandardTokenType {
  other(0),
  comment(1),
  string(2),
  regEx(3);

  const StandardTokenType(this.value);
  final int value;
}

enum OptionalStandardTokenType {
  other(0),
  comment(1),
  string(2),
  regEx(3),
  notSet(8);

  const OptionalStandardTokenType(this.value);
  final int value;
}

OptionalStandardTokenType toOptionalTokenType(StandardTokenType standardType) {
  switch (standardType) {
    case StandardTokenType.other:
      return OptionalStandardTokenType.other;
    case StandardTokenType.comment:
      return OptionalStandardTokenType.comment;
    case StandardTokenType.string:
      return OptionalStandardTokenType.string;
    case StandardTokenType.regEx:
      return OptionalStandardTokenType.regEx;
  }
}

class EncodedTokenAttributes {
  static String toBinaryStr(int encodedTokenAttributes) {
    return encodedTokenAttributes.toRadixString(2).padLeft(32, '0');
  }

  static int getLanguageId(int encodedTokenAttributes) {
    return (encodedTokenAttributes & _languageIdMask) >> _languageIdOffset;
  }

  static StandardTokenType getTokenType(int encodedTokenAttributes) {
    final value = (encodedTokenAttributes & _tokenTypeMask) >> _tokenTypeOffset;
    return StandardTokenType.values.firstWhere((entry) => entry.value == value);
  }

  static bool containsBalancedBrackets(int encodedTokenAttributes) {
    return (encodedTokenAttributes & _balancedBracketsMask) != 0;
  }

  static int getFontStyle(int encodedTokenAttributes) {
    return (encodedTokenAttributes & _fontStyleMask) >> _fontStyleOffset;
  }

  static int getForeground(int encodedTokenAttributes) {
    return (encodedTokenAttributes & _foregroundMask) >> _foregroundOffset;
  }

  static int getBackground(int encodedTokenAttributes) {
    return (encodedTokenAttributes & _backgroundMask) >> _backgroundOffset;
  }

  static int set(
    int encodedTokenAttributes,
    int languageId,
    OptionalStandardTokenType tokenType,
    bool? containsBalancedBrackets,
    int fontStyle,
    int foreground,
    int background,
  ) {
    var currentLanguageId = getLanguageId(encodedTokenAttributes);
    var currentTokenType = getTokenType(encodedTokenAttributes).value;
    var currentBalancedBit =
        EncodedTokenAttributes.containsBalancedBrackets(encodedTokenAttributes)
        ? 1
        : 0;
    var currentFontStyle = getFontStyle(encodedTokenAttributes);
    var currentForeground = getForeground(encodedTokenAttributes);
    var currentBackground = getBackground(encodedTokenAttributes);

    if (languageId != 0) {
      currentLanguageId = languageId;
    }
    if (tokenType != OptionalStandardTokenType.notSet) {
      currentTokenType = tokenType.value;
    }
    if (containsBalancedBrackets != null) {
      currentBalancedBit = containsBalancedBrackets ? 1 : 0;
    }
    if (fontStyle != FontStyle.notSet) {
      currentFontStyle = fontStyle;
    }
    if (foreground != 0) {
      currentForeground = foreground;
    }
    if (background != 0) {
      currentBackground = background;
    }

    return ((currentLanguageId << _languageIdOffset) |
            (currentTokenType << _tokenTypeOffset) |
            (currentBalancedBit << _balancedBracketsOffset) |
            (currentFontStyle << _fontStyleOffset) |
            (currentForeground << _foregroundOffset) |
            (currentBackground << _backgroundOffset)) &
        0xffffffff;
  }
}

const int _languageIdMask = 0x000000ff;
const int _tokenTypeMask = 0x00000300;
const int _balancedBracketsMask = 0x00000400;
const int _fontStyleMask = 0x00007800;
const int _foregroundMask = 0x00ff8000;
const int _backgroundMask = 0xff000000;

const int _languageIdOffset = 0;
const int _tokenTypeOffset = 8;
const int _balancedBracketsOffset = 10;
const int _fontStyleOffset = 11;
const int _foregroundOffset = 15;
const int _backgroundOffset = 24;
