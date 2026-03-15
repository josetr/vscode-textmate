import 'encodedTokenAttributes.dart';
import 'grammar/grammar.dart';
import 'onigLib.dart';
import 'rawGrammar.dart';
import 'theme.dart';

class SyncRegistry implements IGrammarRepository, IThemeProvider {
  SyncRegistry(Theme theme, this._onigLibPromise) : _theme = theme;

  final Map<ScopeName, Grammar> _grammars = <ScopeName, Grammar>{};
  final Map<ScopeName, RawGrammar> _rawGrammars = <ScopeName, RawGrammar>{};
  final Map<ScopeName, List<ScopeName>> _injectionGrammars =
      <ScopeName, List<ScopeName>>{};
  Theme _theme;
  final Future<OnigLib> _onigLibPromise;

  void dispose() {
    for (final grammar in _grammars.values) {
      grammar.dispose();
    }
  }

  void setTheme(Theme theme) {
    _theme = theme;
  }

  List<String> getColorMap() => _theme.getColorMap();

  // Add `grammar` to registry and return a list of referenced scope names.
  void addGrammar(RawGrammar grammar, [List<ScopeName>? injectionScopeNames]) {
    _rawGrammars[grammar.scopeName] = grammar;
    if (injectionScopeNames != null) {
      _injectionGrammars[grammar.scopeName] = List<ScopeName>.from(
        injectionScopeNames,
      );
    }
  }

  @override
  RawGrammar? lookup(ScopeName scopeName) => _rawGrammars[scopeName];

  @override
  List<ScopeName> injections(ScopeName targetScope) {
    return _injectionGrammars[targetScope] ?? const <ScopeName>[];
  }

  @override
  StyleAttributes getDefaults() => _theme.getDefaults();

  @override
  StyleAttributes? themeMatch(ScopeStack? scopePath) => _theme.match(scopePath);

  Future<Grammar?> grammarForScopeName(
    ScopeName scopeName,
    int initialLanguage,
    Map<String, int>? embeddedLanguages,
    Map<String, StandardTokenType>? tokenTypes,
    BalancedBracketSelectors? balancedBracketSelectors,
  ) async {
    if (!_grammars.containsKey(scopeName)) {
      final rawGrammar = _rawGrammars[scopeName];
      if (rawGrammar == null) {
        return null;
      }
      _grammars[scopeName] = createGrammar(
        scopeName,
        rawGrammar,
        initialLanguage,
        embeddedLanguages,
        tokenTypes,
        balancedBracketSelectors,
        this,
        this,
        await _onigLibPromise,
      );
    }
    return _grammars[scopeName];
  }
}
