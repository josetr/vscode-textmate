import '../encodedTokenAttributes.dart';
import '../theme.dart';
import '../utils.dart';

class BasicScopeAttributes {
  const BasicScopeAttributes(this.languageId, this.tokenType);

  final int languageId;
  final OptionalStandardTokenType tokenType;
}

class BasicScopeAttributesProvider {
  BasicScopeAttributesProvider(
    int initialLanguageId,
    Map<String, int>? embeddedLanguages,
  ) : _defaultAttributes = BasicScopeAttributes(
        initialLanguageId,
        OptionalStandardTokenType.notSet,
      ),
      _embeddedLanguagesMatcher = _ScopeMatcher<int>(
        (embeddedLanguages ?? <String, int>{}).entries
            .map((entry) => MapEntry(entry.key, entry.value))
            .toList(growable: false),
      );

  final BasicScopeAttributes _defaultAttributes;
  final _ScopeMatcher<int> _embeddedLanguagesMatcher;
  static const BasicScopeAttributes _nullScopeMetadata = BasicScopeAttributes(
    0,
    OptionalStandardTokenType.other,
  );

  late final CachedFn<ScopeName, BasicScopeAttributes>
  _getBasicScopeAttributes = CachedFn<ScopeName, BasicScopeAttributes>((
    scopeName,
  ) {
    final languageId = _scopeToLanguage(scopeName);
    final standardTokenType = _toStandardTokenType(scopeName);
    return BasicScopeAttributes(languageId, standardTokenType);
  });

  BasicScopeAttributes getDefaultAttributes() => _defaultAttributes;

  BasicScopeAttributes getBasicScopeAttributes(ScopeName? scopeName) {
    if (scopeName == null) {
      return _nullScopeMetadata;
    }
    return _getBasicScopeAttributes.get(scopeName);
  }

  int _scopeToLanguage(ScopeName scope) {
    return _embeddedLanguagesMatcher.match(scope) ?? 0;
  }

  OptionalStandardTokenType _toStandardTokenType(ScopeName scopeName) {
    final match = _standardTokenTypeRegExp.firstMatch(scopeName);
    if (match == null) {
      return OptionalStandardTokenType.notSet;
    }
    switch (match.group(1)) {
      case 'comment':
        return OptionalStandardTokenType.comment;
      case 'string':
        return OptionalStandardTokenType.string;
      case 'regex':
        return OptionalStandardTokenType.regEx;
      case 'meta.embedded':
        return OptionalStandardTokenType.other;
    }
    throw StateError('Unexpected match for standard token type');
  }
}

final RegExp _standardTokenTypeRegExp = RegExp(
  r'\b(comment|string|regex|meta\.embedded)\b',
);

class _ScopeMatcher<TValue> {
  _ScopeMatcher(List<MapEntry<ScopeName, TValue>> values)
    : values = values.isEmpty ? null : Map<String, TValue>.fromEntries(values),
      scopesRegExp = values.isEmpty ? null : _buildRegExp(values);

  final Map<String, TValue>? values;
  final RegExp? scopesRegExp;

  static RegExp _buildRegExp<TValue>(List<MapEntry<ScopeName, TValue>> values) {
    final escapedScopes =
        values
            .map((entry) => escapeRegExpCharacters(entry.key))
            .toList(growable: true)
          ..sort(
            (a, b) =>
                b.length - a.length != 0 ? b.length - a.length : a.compareTo(b),
          );
    return RegExp('^((${escapedScopes.join(')|(')}))(\$|\\.)');
  }

  TValue? match(ScopeName scope) {
    if (scopesRegExp == null || values == null) {
      return null;
    }
    final match = scopesRegExp!.firstMatch(scope);
    if (match == null) {
      return null;
    }
    return values![match.group(1)!];
  }
}
