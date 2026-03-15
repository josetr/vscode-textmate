import 'dart:typed_data';

import 'basicScopesAttributeProvider.dart';
import '../debug.dart';
import '../encodedTokenAttributes.dart';
import 'grammarDependencies.dart' as deps;
import '../matcher.dart';
import '../onigLib.dart';
import '../rawGrammar.dart';
import '../rule.dart';
import '../theme.dart';
import '../utils.dart';

part 'tokenizeString.dart';

abstract class IThemeProvider {
  StyleAttributes? themeMatch(ScopeStack? scopePath);

  StyleAttributes getDefaults();
}

typedef IGrammarRepository = deps.GrammarRepository;

Grammar createGrammar(
  ScopeName scopeName,
  RawGrammar grammar,
  int initialLanguage,
  Map<String, int>? embeddedLanguages,
  Map<String, StandardTokenType>? tokenTypes,
  BalancedBracketSelectors? balancedBracketSelectors,
  deps.GrammarRepository grammarRepository,
  IThemeProvider themeProvider,
  OnigLib onigLib,
) {
  return Grammar(
    scopeName,
    grammar,
    initialLanguage,
    embeddedLanguages,
    tokenTypes,
    balancedBracketSelectors,
    grammarRepository,
    themeProvider,
    onigLib,
  );
}

class Injection {
  const Injection({
    required this.debugSelector,
    required this.matcher,
    required this.priority,
    required this.ruleId,
    required this.grammar,
  });

  final String debugSelector;
  final Matcher<List<String>> matcher;
  final int priority;
  final RuleId ruleId;
  final RawGrammar grammar;
}

void collectInjections(
  List<Injection> result,
  String selector,
  RawRule rule,
  RuleFactoryHelper ruleFactoryHelper,
  RawGrammar grammar,
) {
  final matchers = createMatchers<List<String>>(selector, nameMatcher);
  final ruleId = RuleFactory.getCompiledRuleId(
    rule,
    ruleFactoryHelper,
    grammar.repository,
  );
  for (final matcher in matchers) {
    result.add(
      Injection(
        debugSelector: selector,
        matcher: matcher.matcher,
        ruleId: ruleId,
        grammar: grammar,
        priority: matcher.priority,
      ),
    );
  }
}

class Token {
  Token({
    required this.startIndex,
    required this.endIndex,
    required this.scopes,
  });

  int startIndex;
  final int endIndex;
  final List<String> scopes;
}

class FontInfo {
  FontInfo(
    this.startIndex,
    this.endIndex,
    this.fontFamily,
    this.fontSizeMultiplier,
    this.lineHeightMultiplier,
  );

  int startIndex;
  int endIndex;
  final String? fontFamily;
  final double? fontSizeMultiplier;
  final double? lineHeightMultiplier;

  bool optionsEqual(FontInfo other) {
    return fontFamily == other.fontFamily &&
        fontSizeMultiplier == other.fontSizeMultiplier &&
        lineHeightMultiplier == other.lineHeightMultiplier;
  }
}

class TokenizeLineResult {
  const TokenizeLineResult({
    required this.tokens,
    required this.fonts,
    required this.ruleStack,
    required this.stoppedEarly,
  });

  final List<Token> tokens;
  final List<FontInfo> fonts;
  final StateStack ruleStack;
  final bool stoppedEarly;
}

class TokenizeLineResult2 {
  const TokenizeLineResult2({
    required this.tokens,
    required this.fonts,
    required this.ruleStack,
    required this.stoppedEarly,
  });

  final Uint32List tokens;
  final List<FontInfo> fonts;
  final StateStack ruleStack;
  final bool stoppedEarly;
}

class _LineTokenizeResult {
  const _LineTokenizeResult({
    required this.lineLength,
    required this.lineTokens,
    required this.lineFonts,
    required this.ruleStack,
    required this.stoppedEarly,
  });

  final int lineLength;
  final LineTokens lineTokens;
  final LineFonts lineFonts;
  final StateStackImpl ruleStack;
  final bool stoppedEarly;
}

class TokenTypeMatcher {
  const TokenTypeMatcher({required this.matcher, required this.type});

  final Matcher<List<String>> matcher;
  final StandardTokenType type;
}

class Grammar
    implements RuleFactoryHelper, OnigRuleRegistry, AttributedScopeResolver {
  Grammar(
    this._rootScopeName,
    RawGrammar grammar,
    int initialLanguage,
    Map<String, int>? embeddedLanguages,
    Map<String, StandardTokenType>? tokenTypes,
    this.balancedBracketSelectors,
    this._grammarRepository,
    this._themeProvider,
    this._onigLib,
  ) : _basicScopeAttributesProvider = BasicScopeAttributesProvider(
        initialLanguage,
        embeddedLanguages,
      ),
      _grammar = initGrammar(grammar, null) {
    if (tokenTypes != null) {
      for (final entry in tokenTypes.entries) {
        final matchers = createMatchers<List<String>>(entry.key, nameMatcher);
        for (final matcher in matchers) {
          _tokenTypeMatchers.add(
            TokenTypeMatcher(matcher: matcher.matcher, type: entry.value),
          );
        }
      }
    }
  }

  final ScopeName _rootScopeName;
  final BalancedBracketSelectors? balancedBracketSelectors;
  final deps.GrammarRepository _grammarRepository;
  final IThemeProvider _themeProvider;
  final OnigLib _onigLib;
  final BasicScopeAttributesProvider _basicScopeAttributesProvider;
  final RawGrammar _grammar;
  final Map<ScopeName, RawGrammar> _includedGrammars =
      <ScopeName, RawGrammar>{};
  final List<TokenTypeMatcher> _tokenTypeMatchers = <TokenTypeMatcher>[];
  final List<Rule?> _ruleId2desc = <Rule?>[null];

  int _rootId = -1;
  int _lastRuleId = 0;
  List<Injection>? _injections;

  @override
  IThemeProvider get themeProvider => _themeProvider;

  void dispose() {
    for (final rule in _ruleId2desc) {
      rule?.dispose();
    }
  }

  @override
  OnigScanner createOnigScanner(List<String> sources) {
    return _onigLib.createOnigScanner(sources);
  }

  @override
  OnigString createOnigString(String value) {
    return _onigLib.createOnigString(value);
  }

  @override
  BasicScopeAttributes getMetadataForScope(String scope) {
    return _basicScopeAttributesProvider.getBasicScopeAttributes(scope);
  }

  List<Injection> _collectInjections() {
    final result = <Injection>[];
    final grammar = _rootScopeName == _grammar.scopeName
        ? _grammar
        : getExternalGrammar(_rootScopeName, _grammar.repository);
    if (grammar != null) {
      final rawInjections = grammar.injections;
      if (rawInjections != null) {
        for (final entry in rawInjections.entries) {
          collectInjections(result, entry.key, entry.value, this, grammar);
        }
      }

      final injectionScopeNames = _grammarRepository.injections(_rootScopeName);
      for (final injectionScopeName in injectionScopeNames) {
        final injectionGrammar = getExternalGrammar(
          injectionScopeName,
          _grammar.repository,
        );
        if (injectionGrammar != null) {
          final selector = injectionGrammar.injectionSelector;
          if (selector != null) {
            collectInjections(
              result,
              selector,
              RawRule(
                id: injectionGrammar.repository[r'$self']?.id,
                include: injectionGrammar.repository[r'$self']?.include,
                name: injectionGrammar.scopeName,
                contentName: injectionGrammar.repository[r'$self']?.contentName,
                match: injectionGrammar.repository[r'$self']?.match,
                captures: injectionGrammar.repository[r'$self']?.captures,
                begin: injectionGrammar.repository[r'$self']?.begin,
                beginCaptures:
                    injectionGrammar.repository[r'$self']?.beginCaptures,
                end: injectionGrammar.repository[r'$self']?.end,
                endCaptures: injectionGrammar.repository[r'$self']?.endCaptures,
                whilePattern:
                    injectionGrammar.repository[r'$self']?.whilePattern,
                whileCaptures:
                    injectionGrammar.repository[r'$self']?.whileCaptures,
                patterns: injectionGrammar.repository[r'$self']?.patterns,
                repository: injectionGrammar.repository,
                applyEndPatternLast:
                    injectionGrammar.repository[r'$self']?.applyEndPatternLast,
                location: injectionGrammar.repository[r'$self']?.location,
              ),
              this,
              injectionGrammar,
            );
          }
        }
      }
    }

    result.sort((a, b) => a.priority.compareTo(b.priority));
    return result;
  }

  List<Injection> getInjections() {
    _injections ??= _collectInjections();
    return _injections!;
  }

  @override
  T registerRule<T extends Rule>(T Function(RuleId id) factory) {
    final id = ++_lastRuleId;
    while (_ruleId2desc.length <= id) {
      _ruleId2desc.add(_placeholderRule);
    }
    final result = factory(ruleIdFromNumber(id));
    _ruleId2desc[id] = result;
    return result;
  }

  @override
  Rule getRule(RuleId ruleId) {
    final index = ruleIdToNumber(ruleId);
    if (index < 0 || index >= _ruleId2desc.length) {
      return _placeholderRule;
    }
    return _ruleId2desc[index] ?? _placeholderRule;
  }

  @override
  RawGrammar? getExternalGrammar(String scopeName, RawRepository repository) {
    final cached = _includedGrammars[scopeName];
    if (cached != null) {
      return cached;
    }
    final rawIncludedGrammar = _grammarRepository.lookup(scopeName);
    if (rawIncludedGrammar == null) {
      return null;
    }
    final initialized = initGrammar(rawIncludedGrammar, repository[r'$base']);
    _includedGrammars[scopeName] = initialized;
    return initialized;
  }

  TokenizeLineResult tokenizeLine(
    String lineText,
    StateStack? prevState, [
    int timeLimit = 0,
  ]) {
    final result = _tokenize(
      lineText,
      prevState as StateStackImpl?,
      false,
      timeLimit,
    );
    return TokenizeLineResult(
      tokens: result.lineTokens.getResult(result.ruleStack, result.lineLength),
      fonts: result.lineFonts.getResult(),
      ruleStack: result.ruleStack,
      stoppedEarly: result.stoppedEarly,
    );
  }

  TokenizeLineResult2 tokenizeLine2(
    String lineText,
    StateStack? prevState, [
    int timeLimit = 0,
  ]) {
    final result = _tokenize(
      lineText,
      prevState as StateStackImpl?,
      true,
      timeLimit,
    );
    return TokenizeLineResult2(
      tokens: result.lineTokens.getBinaryResult(
        result.ruleStack,
        result.lineLength,
      ),
      fonts: result.lineFonts.getResult(),
      ruleStack: result.ruleStack,
      stoppedEarly: result.stoppedEarly,
    );
  }

  _LineTokenizeResult _tokenize(
    String lineText,
    StateStackImpl? prevState,
    bool emitBinaryTokens,
    int timeLimit,
  ) {
    if (_rootId == -1) {
      _rootId = RuleFactory.getCompiledRuleId(
        _grammar.repository[r'$self']!,
        this,
        _grammar.repository,
      );
      getInjections();
    }

    late bool isFirstLine;
    if (prevState == null || identical(prevState, StateStackImpl.nullStack)) {
      isFirstLine = true;
      final rawDefaultMetadata = _basicScopeAttributesProvider
          .getDefaultAttributes();
      final defaultStyle = themeProvider.getDefaults();
      final defaultMetadata = EncodedTokenAttributes.set(
        0,
        rawDefaultMetadata.languageId,
        rawDefaultMetadata.tokenType,
        null,
        defaultStyle.fontStyle,
        defaultStyle.foregroundId,
        defaultStyle.backgroundId,
      );
      final fontAttribute = FontAttribute.from(
        defaultStyle.fontFamily,
        defaultStyle.fontSize,
        defaultStyle.lineHeight,
      );

      final rootScopeName = getRule(_rootId).getName(null, null);
      final scopeList = rootScopeName != null
          ? AttributedScopeStack.createRootAndLookUpScopeName(
              rootScopeName,
              defaultMetadata,
              fontAttribute,
              this,
            )
          : AttributedScopeStack.createRoot(
              'unknown',
              defaultMetadata,
              fontAttribute,
            );

      prevState = StateStackImpl(
        null,
        _rootId,
        -1,
        -1,
        false,
        null,
        scopeList,
        scopeList,
      );
    } else {
      isFirstLine = false;
      prevState.reset();
    }

    final appendedLineText = '$lineText\n';
    final onigLineText = createOnigString(appendedLineText);
    final lineLength = onigLineText.content.length;
    final lineTokens = LineTokens(
      emitBinaryTokens,
      appendedLineText,
      _tokenTypeMatchers,
      balancedBracketSelectors,
    );
    final lineFonts = LineFonts();
    final result = _tokenizeString(
      this,
      onigLineText,
      isFirstLine,
      0,
      prevState,
      lineTokens,
      lineFonts,
      true,
      timeLimit,
    );

    disposeOnigString(onigLineText);

    return _LineTokenizeResult(
      lineLength: lineLength,
      lineTokens: lineTokens,
      lineFonts: lineFonts,
      ruleStack: result.stack,
      stoppedEarly: result.stoppedEarly,
    );
  }
}

final Rule _placeholderRule = _PlaceholderRule();

class _PlaceholderRule extends Rule {
  _PlaceholderRule() : super(null, -1, null, null);

  @override
  void collectPatterns(RuleRegistry grammar, RegExpSourceList out) {}

  @override
  CompiledRule<int> compile(OnigRuleRegistry grammar, String? endRegexSource) {
    throw StateError('Placeholder rule cannot be compiled');
  }

  @override
  CompiledRule<int> compileAG(
    OnigRuleRegistry grammar,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  ) {
    throw StateError('Placeholder rule cannot be compiled');
  }

  @override
  void dispose() {}
}

RawGrammar initGrammar(RawGrammar grammar, RawRule? base) {
  final clone = _cloneRawGrammar(grammar);
  final selfRule = RawRule(
    location: clone.location,
    patterns: clone.patterns,
    name: clone.scopeName,
  );
  clone.repository.values[r'$self'] = selfRule;
  clone.repository.values[r'$base'] = base ?? selfRule;
  return clone;
}

abstract class AttributedScopeResolver {
  BasicScopeAttributes getMetadataForScope(String scope);

  IThemeProvider get themeProvider;
}

class AttributedScopeStackFrame {
  const AttributedScopeStackFrame({
    required this.encodedTokenAttributes,
    required this.scopeNames,
  });

  final int encodedTokenAttributes;
  final List<String> scopeNames;
}

class AttributedScopeStack {
  const AttributedScopeStack(
    this.parent,
    this.scopePath,
    this.tokenAttributes,
    this.fontAttributes,
    this.styleAttributes,
  );

  final AttributedScopeStack? parent;
  final ScopeStack scopePath;
  final int tokenAttributes;
  final FontAttribute? fontAttributes;
  final StyleAttributes? styleAttributes;

  static AttributedScopeStack? fromExtension(
    AttributedScopeStack? namesScopeList,
    List<AttributedScopeStackFrame> contentNameScopesList,
  ) {
    var current = namesScopeList;
    var scopeNames = namesScopeList?.scopePath;
    for (final frame in contentNameScopesList) {
      scopeNames = ScopeStack.push(scopeNames, frame.scopeNames);
      current = AttributedScopeStack(
        current,
        scopeNames!,
        frame.encodedTokenAttributes,
        null,
        null,
      );
    }
    return current;
  }

  static AttributedScopeStack createRoot(
    ScopeName scopeName,
    int tokenAttributes,
    FontAttribute fontAttribute,
  ) {
    return AttributedScopeStack(
      null,
      ScopeStack(null, scopeName),
      tokenAttributes,
      fontAttribute,
      null,
    );
  }

  static AttributedScopeStack createRootAndLookUpScopeName(
    ScopeName scopeName,
    int tokenAttributes,
    FontAttribute fontAttribute,
    AttributedScopeResolver grammar,
  ) {
    final rawRootMetadata = grammar.getMetadataForScope(scopeName);
    final scopePath = ScopeStack(null, scopeName);
    final rootStyle = grammar.themeProvider.themeMatch(scopePath);

    final resolvedTokenAttributes = _mergeAttributes(
      tokenAttributes,
      rawRootMetadata,
      rootStyle,
    );
    final resolvedFontAttributes = fontAttribute.withStyle(rootStyle);

    return AttributedScopeStack(
      null,
      scopePath,
      resolvedTokenAttributes,
      resolvedFontAttributes,
      rootStyle,
    );
  }

  ScopeName get scopeName => scopePath.scopeName;

  @override
  String toString() => getScopeNames().join(' ');

  bool equals(AttributedScopeStack? other) => equalsStacks(this, other);

  static bool equalsStacks(AttributedScopeStack? a, AttributedScopeStack? b) {
    while (true) {
      if (identical(a, b)) {
        return true;
      }
      if (a == null && b == null) {
        return true;
      }
      if (a == null || b == null) {
        return false;
      }
      if (a.scopeName != b.scopeName ||
          a.tokenAttributes != b.tokenAttributes) {
        return false;
      }
      a = a.parent;
      b = b.parent;
    }
  }

  static int _mergeAttributes(
    int existingTokenAttributes,
    BasicScopeAttributes basicScopeAttributes,
    StyleAttributes? styleAttributes,
  ) {
    var fontStyle = FontStyle.notSet;
    var foreground = 0;
    var background = 0;

    if (styleAttributes != null) {
      fontStyle = styleAttributes.fontStyle;
      foreground = styleAttributes.foregroundId;
      background = styleAttributes.backgroundId;
    }

    return EncodedTokenAttributes.set(
      existingTokenAttributes,
      basicScopeAttributes.languageId,
      basicScopeAttributes.tokenType,
      null,
      fontStyle,
      foreground,
      background,
    );
  }

  AttributedScopeStack pushAttributed(
    ScopePath? scopePath,
    AttributedScopeResolver grammar,
  ) {
    if (scopePath == null) {
      return this;
    }

    if (!scopePath.contains(' ')) {
      return _pushAttributed(this, scopePath, grammar);
    }

    var result = this;
    for (final scope in scopePath.split(' ')) {
      result = _pushAttributed(result, scope, grammar);
    }
    return result;
  }

  static AttributedScopeStack _pushAttributed(
    AttributedScopeStack target,
    ScopeName scopeName,
    AttributedScopeResolver grammar,
  ) {
    final rawMetadata = grammar.getMetadataForScope(scopeName);
    final newPath = target.scopePath.pushScope(scopeName);
    final scopeThemeMatchResult = grammar.themeProvider.themeMatch(newPath);
    final metadata = _mergeAttributes(
      target.tokenAttributes,
      rawMetadata,
      scopeThemeMatchResult,
    );
    final fontAttributes = target.fontAttributes?.withStyle(
      scopeThemeMatchResult,
    );
    return AttributedScopeStack(
      target,
      newPath,
      metadata,
      fontAttributes,
      scopeThemeMatchResult,
    );
  }

  List<String> getScopeNames() => scopePath.getSegments();

  List<AttributedScopeStackFrame>? getExtensionIfDefined(
    AttributedScopeStack? base,
  ) {
    final result = <AttributedScopeStackFrame>[];
    AttributedScopeStack? self = this;

    while (self != null && !identical(self, base)) {
      result.add(
        AttributedScopeStackFrame(
          encodedTokenAttributes: self.tokenAttributes,
          scopeNames:
              self.scopePath.getExtensionIfDefined(self.parent?.scopePath) ??
              const <String>[],
        ),
      );
      self = self.parent;
    }
    return identical(self, base)
        ? result.reversed.toList(growable: false)
        : null;
  }
}

abstract class StateStack {
  int get depth;

  StateStack clone();

  bool equals(covariant StateStack other);
}

class StateStackFrame {
  const StateStackFrame({
    required this.ruleId,
    this.enterPos,
    this.anchorPos,
    required this.beginRuleCapturedEOL,
    required this.endRule,
    required this.nameScopesList,
    required this.contentNameScopesList,
  });

  final int ruleId;
  final int? enterPos;
  final int? anchorPos;
  final bool beginRuleCapturedEOL;
  final String? endRule;
  final List<AttributedScopeStackFrame> nameScopesList;
  final List<AttributedScopeStackFrame> contentNameScopesList;
}

class StateStackImpl implements StateStack {
  StateStackImpl(
    this.parent,
    this.ruleId,
    int enterPos,
    int anchorPos,
    this.beginRuleCapturedEOL,
    this.endRule,
    this.nameScopesList,
    this.contentNameScopesList,
  ) : depth = parent != null ? parent.depth + 1 : 1,
      _enterPos = enterPos,
      _anchorPos = anchorPos;

  static final StateStackImpl nullStack = StateStackImpl(
    null,
    0,
    0,
    0,
    false,
    null,
    null,
    null,
  );

  final StateStackImpl? parent;
  final RuleId ruleId;
  @override
  final int depth;
  int _enterPos;
  int _anchorPos;
  final bool beginRuleCapturedEOL;
  final String? endRule;
  final AttributedScopeStack? nameScopesList;
  final AttributedScopeStack? contentNameScopesList;

  @override
  bool equals(covariant StateStackImpl other) {
    return _equals(this, other);
  }

  static bool _equals(StateStackImpl a, StateStackImpl b) {
    if (identical(a, b)) {
      return true;
    }
    if (!_structuralEquals(a, b)) {
      return false;
    }
    return AttributedScopeStack.equalsStacks(
      a.contentNameScopesList,
      b.contentNameScopesList,
    );
  }

  static bool _structuralEquals(StateStackImpl? a, StateStackImpl? b) {
    while (true) {
      if (identical(a, b)) {
        return true;
      }
      if (a == null && b == null) {
        return true;
      }
      if (a == null || b == null) {
        return false;
      }
      if (a.depth != b.depth ||
          a.ruleId != b.ruleId ||
          a.endRule != b.endRule) {
        return false;
      }
      a = a.parent;
      b = b.parent;
    }
  }

  @override
  StateStackImpl clone() => this;

  static void _reset(StateStackImpl? element) {
    while (element != null) {
      element._enterPos = -1;
      element._anchorPos = -1;
      element = element.parent;
    }
  }

  void reset() {
    _reset(this);
  }

  StateStackImpl? pop() => parent;

  StateStackImpl safePop() => parent ?? this;

  StateStackImpl push(
    RuleId ruleId,
    int enterPos,
    int anchorPos,
    bool beginRuleCapturedEOL,
    String? endRule,
    AttributedScopeStack? nameScopesList,
    AttributedScopeStack? contentNameScopesList,
  ) {
    return StateStackImpl(
      this,
      ruleId,
      enterPos,
      anchorPos,
      beginRuleCapturedEOL,
      endRule,
      nameScopesList,
      contentNameScopesList,
    );
  }

  int getEnterPos() => _enterPos;

  int getAnchorPos() => _anchorPos;

  Rule getRule(RuleRegistry grammar) => grammar.getRule(ruleId);

  @override
  String toString() {
    final result = <String>[];
    _writeString(result);
    return '[${result.join(',')}]';
  }

  void _writeString(List<String> result) {
    parent?._writeString(result);
    result.add(
      '($ruleId, ${nameScopesList?.toString()}, ${contentNameScopesList?.toString()})',
    );
  }

  StateStackImpl withContentNameScopesList(
    AttributedScopeStack contentNameScopeStack,
  ) {
    if (identical(contentNameScopesList, contentNameScopeStack)) {
      return this;
    }
    return parent!.push(
      ruleId,
      _enterPos,
      _anchorPos,
      beginRuleCapturedEOL,
      endRule,
      nameScopesList,
      contentNameScopeStack,
    );
  }

  StateStackImpl withEndRule(String endRule) {
    if (this.endRule == endRule) {
      return this;
    }
    return StateStackImpl(
      parent,
      ruleId,
      _enterPos,
      _anchorPos,
      beginRuleCapturedEOL,
      endRule,
      nameScopesList,
      contentNameScopesList,
    );
  }

  bool hasSameRuleAs(StateStackImpl other) {
    StateStackImpl? element = this;
    while (element != null && element._enterPos == other._enterPos) {
      if (element.ruleId == other.ruleId) {
        return true;
      }
      element = element.parent;
    }
    return false;
  }

  StateStackFrame toStateStackFrame() {
    return StateStackFrame(
      ruleId: ruleIdToNumber(ruleId),
      beginRuleCapturedEOL: beginRuleCapturedEOL,
      endRule: endRule,
      nameScopesList:
          nameScopesList?.getExtensionIfDefined(parent?.nameScopesList) ??
          const <AttributedScopeStackFrame>[],
      contentNameScopesList:
          contentNameScopesList?.getExtensionIfDefined(nameScopesList) ??
          const <AttributedScopeStackFrame>[],
      enterPos: _enterPos,
      anchorPos: _anchorPos,
    );
  }

  static StateStackImpl pushFrame(StateStackImpl? self, StateStackFrame frame) {
    final namesScopeList = AttributedScopeStack.fromExtension(
      self?.nameScopesList,
      frame.nameScopesList,
    );
    return StateStackImpl(
      self,
      ruleIdFromNumber(frame.ruleId),
      frame.enterPos ?? -1,
      frame.anchorPos ?? -1,
      frame.beginRuleCapturedEOL,
      frame.endRule,
      namesScopeList,
      AttributedScopeStack.fromExtension(
        namesScopeList,
        frame.contentNameScopesList,
      ),
    );
  }
}

class BalancedBracketSelectors {
  BalancedBracketSelectors(
    List<String> balancedBracketScopes,
    List<String> unbalancedBracketScopes,
  ) : balancedBracketScopes = balancedBracketScopes
          .expand((selector) {
            if (selector == '*') {
              return const <Matcher<List<String>>>[];
            }
            return createMatchers<List<String>>(
              selector,
              nameMatcher,
            ).map((matcher) => matcher.matcher);
          })
          .toList(growable: false),
      unbalancedBracketScopes = unbalancedBracketScopes
          .expand(
            (selector) => createMatchers<List<String>>(
              selector,
              nameMatcher,
            ).map((matcher) => matcher.matcher),
          )
          .toList(growable: false),
      allowAny = balancedBracketScopes.contains('*');

  final List<Matcher<List<String>>> balancedBracketScopes;
  final List<Matcher<List<String>>> unbalancedBracketScopes;
  final bool allowAny;

  bool get matchesAlways => allowAny && unbalancedBracketScopes.isEmpty;

  bool get matchesNever => balancedBracketScopes.isEmpty && !allowAny;

  bool match(List<String> scopes) {
    for (final excluder in unbalancedBracketScopes) {
      if (excluder(scopes)) {
        return false;
      }
    }
    for (final includer in balancedBracketScopes) {
      if (includer(scopes)) {
        return true;
      }
    }
    return allowAny;
  }
}

bool nameMatcher(List<String> identifiers, List<String> scopes) {
  if (scopes.length < identifiers.length) {
    return false;
  }
  var lastIndex = 0;
  for (final identifier in identifiers) {
    var matched = false;
    for (var i = lastIndex; i < scopes.length; i++) {
      if (scopesAreMatching(scopes[i], identifier)) {
        lastIndex = i + 1;
        matched = true;
        break;
      }
    }
    if (!matched) {
      return false;
    }
  }
  return true;
}

bool scopesAreMatching(String thisScopeName, String scopeName) {
  if (thisScopeName.isEmpty) {
    return false;
  }
  if (thisScopeName == scopeName) {
    return true;
  }
  final length = scopeName.length;
  return thisScopeName.length > length &&
      thisScopeName.startsWith(scopeName) &&
      thisScopeName[length] == '.';
}

RawGrammar _cloneRawGrammar(RawGrammar grammar) {
  return RawGrammar(
    repository: _cloneRawRepository(grammar.repository),
    scopeName: grammar.scopeName,
    patterns: grammar.patterns.map(_cloneRawRule).toList(growable: false),
    injections: grammar.injections?.map(
      (key, value) => MapEntry(key, _cloneRawRule(value)),
    ),
    injectionSelector: grammar.injectionSelector,
    fileTypes: grammar.fileTypes == null
        ? null
        : List<String>.from(grammar.fileTypes!),
    name: grammar.name,
    firstLineMatch: grammar.firstLineMatch,
    location: grammar.location,
  );
}

RawRepository _cloneRawRepository(RawRepository repository) {
  return RawRepository(
    values: repository.values.map(
      (key, value) => MapEntry(key, _cloneRawRule(value)),
    ),
    location: repository.location,
  );
}

RawRule _cloneRawRule(RawRule rule) {
  return RawRule(
    id: rule.id,
    include: rule.include,
    name: rule.name,
    contentName: rule.contentName,
    match: rule.match,
    captures: rule.captures?.map(
      (key, value) => MapEntry(key, _cloneRawRule(value)),
    ),
    begin: rule.begin,
    beginCaptures: rule.beginCaptures?.map(
      (key, value) => MapEntry(key, _cloneRawRule(value)),
    ),
    end: rule.end,
    endCaptures: rule.endCaptures?.map(
      (key, value) => MapEntry(key, _cloneRawRule(value)),
    ),
    whilePattern: rule.whilePattern,
    whileCaptures: rule.whileCaptures?.map(
      (key, value) => MapEntry(key, _cloneRawRule(value)),
    ),
    patterns: rule.patterns?.map(_cloneRawRule).toList(growable: false),
    repository: rule.repository == null
        ? null
        : _cloneRawRepository(rule.repository!),
    applyEndPatternLast: rule.applyEndPatternLast,
    location: rule.location,
  );
}

class LineTokens {
  LineTokens(
    this._emitBinaryTokens,
    String lineText,
    this._tokenTypeOverrides,
    this.balancedBracketSelectors,
  ) : _mergeConsecutiveTokensWithEqualMetadata = !containsRTL(lineText);

  final bool _emitBinaryTokens;
  final List<TokenTypeMatcher> _tokenTypeOverrides;
  final BalancedBracketSelectors? balancedBracketSelectors;
  final bool _mergeConsecutiveTokensWithEqualMetadata;
  final List<Token> _tokens = <Token>[];
  final List<int> _binaryTokens = <int>[];
  int _lastTokenEndIndex = 0;

  void produce(StateStackImpl stack, int endIndex) {
    produceFromScopes(stack.contentNameScopesList, endIndex);
  }

  void produceFromScopes(AttributedScopeStack? scopesList, int endIndex) {
    if (_lastTokenEndIndex >= endIndex) {
      return;
    }

    if (_emitBinaryTokens) {
      var metadata = scopesList?.tokenAttributes ?? 0;
      var containsBalancedBrackets = false;
      if (balancedBracketSelectors?.matchesAlways ?? false) {
        containsBalancedBrackets = true;
      }

      if (_tokenTypeOverrides.isNotEmpty ||
          (balancedBracketSelectors != null &&
              !balancedBracketSelectors!.matchesAlways &&
              !balancedBracketSelectors!.matchesNever)) {
        final scopes = scopesList?.getScopeNames() ?? const <String>[];
        for (final tokenType in _tokenTypeOverrides) {
          if (tokenType.matcher(scopes)) {
            metadata = EncodedTokenAttributes.set(
              metadata,
              0,
              toOptionalTokenType(tokenType.type),
              null,
              FontStyle.notSet,
              0,
              0,
            );
          }
        }
        if (balancedBracketSelectors != null) {
          containsBalancedBrackets = balancedBracketSelectors!.match(scopes);
        }
      }

      if (containsBalancedBrackets) {
        metadata = EncodedTokenAttributes.set(
          metadata,
          0,
          OptionalStandardTokenType.notSet,
          true,
          FontStyle.notSet,
          0,
          0,
        );
      }

      if (_mergeConsecutiveTokensWithEqualMetadata &&
          _binaryTokens.isNotEmpty &&
          _binaryTokens.last == metadata) {
        _lastTokenEndIndex = endIndex;
        return;
      }

      _binaryTokens.add(_lastTokenEndIndex);
      _binaryTokens.add(metadata);
      _lastTokenEndIndex = endIndex;
      return;
    }

    _tokens.add(
      Token(
        startIndex: _lastTokenEndIndex,
        endIndex: endIndex,
        scopes: scopesList?.getScopeNames() ?? const <String>[],
      ),
    );
    _lastTokenEndIndex = endIndex;
  }

  List<Token> getResult(StateStackImpl stack, int lineLength) {
    if (_tokens.isNotEmpty && _tokens.last.startIndex == lineLength - 1) {
      _tokens.removeLast();
    }
    if (_tokens.isEmpty) {
      _lastTokenEndIndex = -1;
      produce(stack, lineLength);
      _tokens.last.startIndex = 0;
    }
    return _tokens;
  }

  Uint32List getBinaryResult(StateStackImpl stack, int lineLength) {
    if (_binaryTokens.isNotEmpty &&
        _binaryTokens[_binaryTokens.length - 2] == lineLength - 1) {
      _binaryTokens.removeLast();
      _binaryTokens.removeLast();
    }

    if (_binaryTokens.isEmpty) {
      _lastTokenEndIndex = -1;
      produce(stack, lineLength);
      _binaryTokens[_binaryTokens.length - 2] = 0;
    }

    return Uint32List.fromList(_binaryTokens);
  }
}

class LineFonts {
  final List<FontInfo> _fonts = <FontInfo>[];
  int _lastIndex = 0;

  void produce(StateStackImpl stack, int endIndex) {
    produceFromScopes(stack.contentNameScopesList, endIndex);
  }

  void produceFromScopes(AttributedScopeStack? scopesList, int endIndex) {
    if (scopesList?.fontAttributes == null) {
      _lastIndex = endIndex;
      return;
    }
    final fontFamily = scopesList!.fontAttributes!.fontFamily;
    final fontSizeMultiplier = scopesList.fontAttributes!.fontSize;
    final lineHeightMultiplier = scopesList.fontAttributes!.lineHeight;
    if (fontFamily == null &&
        fontSizeMultiplier == null &&
        lineHeightMultiplier == null) {
      _lastIndex = endIndex;
      return;
    }

    final font = FontInfo(
      _lastIndex,
      endIndex,
      fontFamily,
      fontSizeMultiplier,
      lineHeightMultiplier,
    );
    final lastFont = _fonts.isEmpty ? null : _fonts.last;
    if (lastFont != null &&
        lastFont.endIndex == _lastIndex &&
        lastFont.optionsEqual(font)) {
      lastFont.endIndex = font.endIndex;
    } else {
      _fonts.add(font);
    }
    _lastIndex = endIndex;
  }

  List<FontInfo> getResult() => _fonts;
}
