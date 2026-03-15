import 'encodedTokenAttributes.dart';
import 'grammar/grammar.dart' as grammar;
import 'grammar/grammarDependencies.dart';
import 'onigLib.dart';
import 'parseRawGrammar.dart' as grammarReader;
import 'rawGrammar.dart';
import 'registry.dart';
import 'theme.dart';

export 'diffStateStacks.dart'
    show StackDiff, applyStateStackDiff, diffStateStacksRefEq;
export 'onigLib.dart';

typedef IRawGrammar = RawGrammar;
typedef IRawTheme = RawTheme;

typedef IEmbeddedLanguagesMap = Map<String, int>;
typedef ITokenTypeMap = Map<String, StandardTokenType>;

class RegistryOptions {
  const RegistryOptions({
    required this.onigLib,
    this.theme,
    this.colorMap,
    required this.loadGrammar,
    this.getInjections,
  });

  final Future<OnigLib> onigLib;
  final IRawTheme? theme;
  final List<String>? colorMap;
  final Future<IRawGrammar?> Function(ScopeName scopeName) loadGrammar;
  final List<ScopeName>? Function(ScopeName scopeName)? getInjections;
}

class IGrammarConfiguration {
  const IGrammarConfiguration({
    this.embeddedLanguages,
    this.tokenTypes,
    this.balancedBracketSelectors,
    this.unbalancedBracketSelectors,
  });

  final IEmbeddedLanguagesMap? embeddedLanguages;
  final ITokenTypeMap? tokenTypes;
  final List<String>? balancedBracketSelectors;
  final List<String>? unbalancedBracketSelectors;
}

typedef GrammarConfiguration = IGrammarConfiguration;

class Registry {
  Registry(RegistryOptions options)
    : _options = options,
      _syncRegistry = SyncRegistry(
        Theme.createFromRawTheme(options.theme, options.colorMap),
        options.onigLib,
      );

  final RegistryOptions _options;
  final SyncRegistry _syncRegistry;
  final Map<String, Future<void>> _ensureGrammarCache =
      <String, Future<void>>{};

  void dispose() {
    _syncRegistry.dispose();
  }

  void setTheme(IRawTheme theme, [List<String>? colorMap]) {
    _syncRegistry.setTheme(Theme.createFromRawTheme(theme, colorMap));
  }

  List<String> getColorMap() {
    return _syncRegistry.getColorMap();
  }

  Future<IGrammar?> loadGrammarWithEmbeddedLanguages(
    ScopeName initialScopeName,
    int initialLanguage,
    IEmbeddedLanguagesMap embeddedLanguages,
  ) {
    return loadGrammarWithConfiguration(
      initialScopeName,
      initialLanguage,
      IGrammarConfiguration(embeddedLanguages: embeddedLanguages),
    );
  }

  Future<IGrammar?> loadGrammarWithConfiguration(
    ScopeName initialScopeName,
    int initialLanguage,
    IGrammarConfiguration configuration,
  ) {
    return _loadGrammar(
      initialScopeName,
      initialLanguage,
      configuration.embeddedLanguages,
      configuration.tokenTypes,
      grammar.BalancedBracketSelectors(
        configuration.balancedBracketSelectors ?? const <String>[],
        configuration.unbalancedBracketSelectors ?? const <String>[],
      ),
    );
  }

  Future<IGrammar?> loadGrammar(ScopeName initialScopeName) {
    return _loadGrammar(initialScopeName, 0, null, null, null);
  }

  Future<IGrammar?> _loadGrammar(
    ScopeName initialScopeName,
    int initialLanguage,
    IEmbeddedLanguagesMap? embeddedLanguages,
    ITokenTypeMap? tokenTypes,
    grammar.BalancedBracketSelectors? balancedBracketSelectors,
  ) async {
    final dependencyProcessor = ScopeDependencyProcessor(
      _syncRegistry,
      initialScopeName,
    );
    while (dependencyProcessor.q.isNotEmpty) {
      await Future.wait(
        dependencyProcessor.q.map(
          (request) => _loadSingleGrammar(_scopeOfReference(request)),
        ),
      );
      dependencyProcessor.processQueue();
    }

    return _grammarForScopeName(
      initialScopeName,
      initialLanguage,
      embeddedLanguages,
      tokenTypes,
      balancedBracketSelectors,
    );
  }

  Future<void> _loadSingleGrammar(ScopeName scopeName) {
    return _ensureGrammarCache.putIfAbsent(
      scopeName,
      () => _doLoadSingleGrammar(scopeName),
    );
  }

  Future<void> _doLoadSingleGrammar(ScopeName scopeName) async {
    final grammar = await _options.loadGrammar(scopeName);
    if (grammar != null) {
      final injections = _options.getInjections?.call(scopeName);
      _syncRegistry.addGrammar(grammar, injections);
    }
  }

  Future<IGrammar> addGrammar(
    IRawGrammar rawGrammar, {
    List<String> injections = const <String>[],
    int initialLanguage = 0,
    IEmbeddedLanguagesMap? embeddedLanguages,
  }) async {
    _syncRegistry.addGrammar(rawGrammar, injections);
    return (await _grammarForScopeName(
      rawGrammar.scopeName,
      initialLanguage,
      embeddedLanguages,
      null,
      null,
    ))!;
  }

  Future<IGrammar?> _grammarForScopeName(
    String scopeName,
    int initialLanguage, [
    IEmbeddedLanguagesMap? embeddedLanguages,
    ITokenTypeMap? tokenTypes,
    grammar.BalancedBracketSelectors? balancedBracketSelectors,
  ]) {
    return _syncRegistry.grammarForScopeName(
      scopeName,
      initialLanguage,
      embeddedLanguages,
      tokenTypes,
      balancedBracketSelectors,
    );
  }

  String _scopeOfReference(AbsoluteRuleReference reference) {
    if (reference is TopLevelRuleReference) {
      return reference.scopeName;
    }
    if (reference is TopLevelRepositoryRuleReference) {
      return reference.scopeName;
    }
    throw StateError('Unknown reference type: $reference');
  }
}

typedef IGrammar = grammar.Grammar;
typedef ITokenizeLineResult = grammar.TokenizeLineResult;
typedef ITokenizeLineResult2 = grammar.TokenizeLineResult2;
typedef IFontInfo = grammar.FontInfo;
typedef IToken = grammar.Token;
typedef StateStack = grammar.StateStack;

final StateStack INITIAL = grammar.StateStackImpl.nullStack;
final StateStack initial = INITIAL;

final IRawGrammar Function(String content, [String? filePath]) parseRawGrammar =
    grammarReader.parseRawGrammar;
