import 'grammar/grammarDependencies.dart';
import 'onigLib.dart';
import 'rawGrammar.dart';
import 'utils.dart';

final RegExp _hasBackReferences = RegExp(r'\\(\d+)');
final RegExp _backReferencingEnd = RegExp(r'\\(\d+)');

typedef RuleId = int;

const int endRuleId = -1;
const int whileRuleId = -2;

RuleId ruleIdFromNumber(int id) => id;

int ruleIdToNumber(RuleId id) => id;

abstract class RuleRegistry {
  Rule getRule(RuleId ruleId);

  T registerRule<T extends Rule>(T Function(RuleId id) factory);
}

abstract class GrammarRegistry {
  RawGrammar? getExternalGrammar(String scopeName, RawRepository repository);
}

typedef IRuleRegistry = RuleRegistry;
typedef IGrammarRegistry = GrammarRegistry;

abstract class RuleFactoryHelper implements RuleRegistry, GrammarRegistry {}

typedef IRuleFactoryHelper = RuleFactoryHelper;

abstract class OnigRuleRegistry implements OnigLib, RuleRegistry {}

typedef IOnigRuleRegistry = OnigRuleRegistry;

abstract class Rule {
  Rule(this.location, this.id, String? name, String? contentName)
    : _name = name,
      _nameIsCapturing = RegexSource.hasCaptures(name),
      _contentName = contentName,
      _contentNameIsCapturing = RegexSource.hasCaptures(contentName);

  final Location? location;
  final RuleId id;
  final bool _nameIsCapturing;
  final String? _name;
  final bool _contentNameIsCapturing;
  final String? _contentName;

  void dispose();

  String get debugName {
    final locationLabel = location == null || location!.filename == null
        ? 'unknown'
        : '${basename(location!.filename!)}:${location!.line}';
    return '$runtimeType#$id @ $locationLabel';
  }

  String? getName(String? lineText, List<OnigCaptureIndex>? captureIndices) {
    if (!_nameIsCapturing ||
        _name == null ||
        lineText == null ||
        captureIndices == null) {
      return _name;
    }
    return RegexSource.replaceCaptures(_name, lineText, captureIndices);
  }

  String? getContentName(
    String lineText,
    List<OnigCaptureIndex> captureIndices,
  ) {
    if (!_contentNameIsCapturing || _contentName == null) {
      return _contentName;
    }
    return RegexSource.replaceCaptures(_contentName, lineText, captureIndices);
  }

  void collectPatterns(RuleRegistry grammar, RegExpSourceList out);

  CompiledRule<int> compile(OnigRuleRegistry grammar, String? endRegexSource);

  CompiledRule<int> compileAG(
    OnigRuleRegistry grammar,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  );
}

class CompilePatternsResult {
  const CompilePatternsResult({
    required this.patterns,
    required this.hasMissingPatterns,
  });

  final List<RuleId> patterns;
  final bool hasMissingPatterns;
}

typedef ICompilePatternsResult = CompilePatternsResult;

class CaptureRule extends Rule {
  CaptureRule(
    super.location,
    super.id,
    super.name,
    super.contentName,
    this.retokenizeCapturedWithRuleId,
  );

  final RuleId retokenizeCapturedWithRuleId;

  @override
  void dispose() {}

  @override
  void collectPatterns(RuleRegistry grammar, RegExpSourceList out) {
    throw UnsupportedError('Not supported');
  }

  @override
  CompiledRule<int> compile(OnigRuleRegistry grammar, String? endRegexSource) {
    throw UnsupportedError('Not supported');
  }

  @override
  CompiledRule<int> compileAG(
    OnigRuleRegistry grammar,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  ) {
    throw UnsupportedError('Not supported');
  }
}

class MatchRule extends Rule {
  MatchRule(
    Location? location,
    RuleId id,
    String? name,
    String match,
    this.captures,
  ) : _match = RegExpSource(match, id),
      super(location, id, name, null);

  final RegExpSource<RuleId> _match;
  final List<CaptureRule?> captures;
  RegExpSourceList<int>? _cachedCompiledPatterns;

  @override
  void dispose() {
    _cachedCompiledPatterns?.dispose();
    _cachedCompiledPatterns = null;
  }

  String get debugMatchRegExp => _match.source;

  @override
  void collectPatterns(RuleRegistry grammar, RegExpSourceList out) {
    out.push(_match);
  }

  @override
  CompiledRule<int> compile(OnigRuleRegistry grammar, String? endRegexSource) {
    return _getCachedCompiledPatterns(grammar).compile(grammar);
  }

  @override
  CompiledRule<int> compileAG(
    OnigRuleRegistry grammar,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  ) {
    return _getCachedCompiledPatterns(
      grammar,
    ).compileAG(grammar, allowA, allowG);
  }

  RegExpSourceList<int> _getCachedCompiledPatterns(OnigLib grammar) {
    _cachedCompiledPatterns ??= RegExpSourceList<int>()..push(_match);
    return _cachedCompiledPatterns!;
  }
}

class IncludeOnlyRule extends Rule {
  IncludeOnlyRule(
    super.location,
    super.id,
    super.name,
    super.contentName,
    CompilePatternsResult patterns,
  ) : patterns = patterns.patterns,
      hasMissingPatterns = patterns.hasMissingPatterns;

  final bool hasMissingPatterns;
  final List<RuleId> patterns;
  RegExpSourceList<int>? _cachedCompiledPatterns;

  @override
  void dispose() {
    _cachedCompiledPatterns?.dispose();
    _cachedCompiledPatterns = null;
  }

  @override
  void collectPatterns(RuleRegistry grammar, RegExpSourceList out) {
    for (final pattern in patterns) {
      grammar.getRule(pattern).collectPatterns(grammar, out);
    }
  }

  @override
  CompiledRule<int> compile(OnigRuleRegistry grammar, String? endRegexSource) {
    return _getCachedCompiledPatterns(grammar).compile(grammar);
  }

  @override
  CompiledRule<int> compileAG(
    OnigRuleRegistry grammar,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  ) {
    return _getCachedCompiledPatterns(
      grammar,
    ).compileAG(grammar, allowA, allowG);
  }

  RegExpSourceList<int> _getCachedCompiledPatterns(RuleRegistry grammar) {
    if (_cachedCompiledPatterns == null) {
      final list = RegExpSourceList<int>();
      collectPatterns(grammar, list);
      _cachedCompiledPatterns = list;
    }
    return _cachedCompiledPatterns!;
  }
}

class BeginEndRule extends Rule {
  BeginEndRule(
    super.location,
    super.id,
    super.name,
    super.contentName,
    String begin,
    this.beginCaptures,
    String? end,
    this.endCaptures,
    bool? applyEndPatternLast,
    CompilePatternsResult patterns,
  ) : _begin = RegExpSource(begin, id),
      _end = RegExpSource(end ?? '', endRuleId),
      applyEndPatternLast = applyEndPatternLast ?? false,
      patterns = patterns.patterns,
      hasMissingPatterns = patterns.hasMissingPatterns;

  final RegExpSource<RuleId> _begin;
  final List<CaptureRule?> beginCaptures;
  final RegExpSource<int> _end;
  final List<CaptureRule?> endCaptures;
  final bool applyEndPatternLast;
  final bool hasMissingPatterns;
  final List<RuleId> patterns;
  RegExpSourceList<int>? _cachedCompiledPatterns;

  bool get endHasBackReferences => _end.hasBackReferences;

  @override
  void dispose() {
    _cachedCompiledPatterns?.dispose();
    _cachedCompiledPatterns = null;
  }

  String get debugBeginRegExp => _begin.source;

  String get debugEndRegExp => _end.source;

  String getEndWithResolvedBackReferences(
    String lineText,
    List<OnigCaptureIndex> captureIndices,
  ) {
    return _end.resolveBackReferences(lineText, captureIndices);
  }

  @override
  void collectPatterns(RuleRegistry grammar, RegExpSourceList out) {
    out.push(_begin);
  }

  @override
  CompiledRule<int> compile(OnigRuleRegistry grammar, String? endRegexSource) {
    return _getCachedCompiledPatterns(grammar, endRegexSource).compile(grammar);
  }

  @override
  CompiledRule<int> compileAG(
    OnigRuleRegistry grammar,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  ) {
    return _getCachedCompiledPatterns(
      grammar,
      endRegexSource,
    ).compileAG(grammar, allowA, allowG);
  }

  RegExpSourceList<int> _getCachedCompiledPatterns(
    RuleRegistry grammar,
    String? endRegexSource,
  ) {
    if (_cachedCompiledPatterns == null) {
      final list = RegExpSourceList<int>();
      for (final pattern in patterns) {
        grammar.getRule(pattern).collectPatterns(grammar, list);
      }
      if (applyEndPatternLast) {
        list.push(_end.hasBackReferences ? _end.clone() : _end);
      } else {
        list.unshift(_end.hasBackReferences ? _end.clone() : _end);
      }
      _cachedCompiledPatterns = list;
    }
    if (_end.hasBackReferences) {
      final index = applyEndPatternLast
          ? _cachedCompiledPatterns!.length() - 1
          : 0;
      _cachedCompiledPatterns!.setSource(index, endRegexSource ?? '');
    }
    return _cachedCompiledPatterns!;
  }
}

class BeginWhileRule extends Rule {
  BeginWhileRule(
    super.location,
    super.id,
    super.name,
    super.contentName,
    String begin,
    this.beginCaptures,
    String whilePattern,
    this.whileCaptures,
    CompilePatternsResult patterns,
  ) : _begin = RegExpSource(begin, id),
      _while = RegExpSource(whilePattern, whileRuleId),
      patterns = patterns.patterns,
      hasMissingPatterns = patterns.hasMissingPatterns;

  final RegExpSource<RuleId> _begin;
  final List<CaptureRule?> beginCaptures;
  final List<CaptureRule?> whileCaptures;
  final RegExpSource<int> _while;
  final bool hasMissingPatterns;
  final List<RuleId> patterns;
  RegExpSourceList<int>? _cachedCompiledPatterns;
  RegExpSourceList<int>? _cachedCompiledWhilePatterns;

  bool get whileHasBackReferences => _while.hasBackReferences;

  @override
  void dispose() {
    _cachedCompiledPatterns?.dispose();
    _cachedCompiledPatterns = null;
    _cachedCompiledWhilePatterns?.dispose();
    _cachedCompiledWhilePatterns = null;
  }

  String get debugBeginRegExp => _begin.source;

  String get debugWhileRegExp => _while.source;

  String getWhileWithResolvedBackReferences(
    String lineText,
    List<OnigCaptureIndex> captureIndices,
  ) {
    return _while.resolveBackReferences(lineText, captureIndices);
  }

  @override
  void collectPatterns(RuleRegistry grammar, RegExpSourceList out) {
    out.push(_begin);
  }

  @override
  CompiledRule<int> compile(OnigRuleRegistry grammar, String? endRegexSource) {
    return _getCachedCompiledPatterns(grammar).compile(grammar);
  }

  @override
  CompiledRule<int> compileAG(
    OnigRuleRegistry grammar,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  ) {
    return _getCachedCompiledPatterns(
      grammar,
    ).compileAG(grammar, allowA, allowG);
  }

  RegExpSourceList<int> _getCachedCompiledPatterns(RuleRegistry grammar) {
    if (_cachedCompiledPatterns == null) {
      final list = RegExpSourceList<int>();
      for (final pattern in patterns) {
        grammar.getRule(pattern).collectPatterns(grammar, list);
      }
      _cachedCompiledPatterns = list;
    }
    return _cachedCompiledPatterns!;
  }

  CompiledRule<int> compileWhile(OnigLib grammar, String? endRegexSource) {
    return _getCachedCompiledWhilePatterns(endRegexSource).compile(grammar);
  }

  CompiledRule<int> compileWhileAG(
    OnigLib grammar,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  ) {
    return _getCachedCompiledWhilePatterns(
      endRegexSource,
    ).compileAG(grammar, allowA, allowG);
  }

  RegExpSourceList<int> _getCachedCompiledWhilePatterns(
    String? endRegexSource,
  ) {
    _cachedCompiledWhilePatterns ??= RegExpSourceList<int>()
      ..push(_while.hasBackReferences ? _while.clone() : _while);
    if (_while.hasBackReferences) {
      _cachedCompiledWhilePatterns!.setSource(0, endRegexSource ?? '');
    }
    return _cachedCompiledWhilePatterns!;
  }
}

class RuleFactory {
  static CaptureRule createCaptureRule(
    RuleFactoryHelper helper,
    Location? location,
    String? name,
    String? contentName,
    RuleId retokenizeCapturedWithRuleId,
  ) {
    return helper.registerRule(
      (id) => CaptureRule(
        location,
        id,
        name,
        contentName,
        retokenizeCapturedWithRuleId,
      ),
    );
  }

  static RuleId getCompiledRuleId(
    RawRule desc,
    RuleFactoryHelper helper,
    RawRepository repository,
  ) {
    if (desc.id == null) {
      helper.registerRule((id) {
        desc.id = id;

        if (desc.match != null) {
          return MatchRule(
            desc.location,
            desc.id!,
            desc.name,
            desc.match!,
            _compileCaptures(desc.captures, helper, repository),
          );
        }

        if (desc.begin == null) {
          if (desc.repository != null) {
            repository = RawRepository(
              values: mergeObjects(<String, Object?>{}, <Map<String, Object?>>[
                repository.values.cast<String, Object?>(),
                desc.repository!.values.cast<String, Object?>(),
              ]).cast<String, RawRule>(),
              location: repository.location,
            );
          }
          var patterns = desc.patterns;
          if (patterns == null && desc.include != null) {
            patterns = <RawRule>[RawRule(include: desc.include)];
          }
          return IncludeOnlyRule(
            desc.location,
            desc.id!,
            desc.name,
            desc.contentName,
            _compilePatterns(patterns, helper, repository),
          );
        }

        if (desc.whilePattern != null) {
          return BeginWhileRule(
            desc.location,
            desc.id!,
            desc.name,
            desc.contentName,
            desc.begin!,
            _compileCaptures(
              desc.beginCaptures ?? desc.captures,
              helper,
              repository,
            ),
            desc.whilePattern!,
            _compileCaptures(
              desc.whileCaptures ?? desc.captures,
              helper,
              repository,
            ),
            _compilePatterns(desc.patterns, helper, repository),
          );
        }

        return BeginEndRule(
          desc.location,
          desc.id!,
          desc.name,
          desc.contentName,
          desc.begin!,
          _compileCaptures(
            desc.beginCaptures ?? desc.captures,
            helper,
            repository,
          ),
          desc.end,
          _compileCaptures(
            desc.endCaptures ?? desc.captures,
            helper,
            repository,
          ),
          desc.applyEndPatternLast,
          _compilePatterns(desc.patterns, helper, repository),
        );
      });
    }

    return desc.id!;
  }

  static List<CaptureRule?> _compileCaptures(
    Map<String, RawRule>? captures,
    RuleFactoryHelper helper,
    RawRepository repository,
  ) {
    final result = <CaptureRule?>[];

    if (captures != null) {
      var maximumCaptureId = 0;
      for (final captureId in captures.keys) {
        final numericCaptureId = int.parse(captureId);
        if (numericCaptureId > maximumCaptureId) {
          maximumCaptureId = numericCaptureId;
        }
      }

      result.length = maximumCaptureId + 1;

      for (final entry in captures.entries) {
        final numericCaptureId = int.parse(entry.key);
        var retokenizeCapturedWithRuleId = 0;
        if (entry.value.patterns != null) {
          retokenizeCapturedWithRuleId = getCompiledRuleId(
            entry.value,
            helper,
            repository,
          );
        }
        result[numericCaptureId] = createCaptureRule(
          helper,
          entry.value.location,
          entry.value.name,
          entry.value.contentName,
          retokenizeCapturedWithRuleId,
        );
      }
    }

    return result;
  }

  static CompilePatternsResult _compilePatterns(
    List<RawRule>? patterns,
    RuleFactoryHelper helper,
    RawRepository repository,
  ) {
    final result = <RuleId>[];

    if (patterns != null) {
      for (final pattern in patterns) {
        var ruleId = -1;

        if (pattern.include != null) {
          switch (parseInclude(pattern.include!)) {
            case BaseReference():
            case SelfReference():
              ruleId = getCompiledRuleId(
                repository[pattern.include!]!,
                helper,
                repository,
              );
            case RelativeReference(:final ruleName):
              final localIncludedRule = repository[ruleName];
              if (localIncludedRule != null) {
                ruleId = getCompiledRuleId(
                  localIncludedRule,
                  helper,
                  repository,
                );
              }
            case TopLevelReference(:final scopeName):
              final externalGrammar = helper.getExternalGrammar(
                scopeName,
                repository,
              );
              if (externalGrammar != null) {
                ruleId = getCompiledRuleId(
                  externalGrammar.repository[r'$self']!,
                  helper,
                  externalGrammar.repository,
                );
              }
            case TopLevelRepositoryReference(:final scopeName, :final ruleName):
              final externalGrammar = helper.getExternalGrammar(
                scopeName,
                repository,
              );
              if (externalGrammar != null) {
                final externalIncludedRule =
                    externalGrammar.repository[ruleName];
                if (externalIncludedRule != null) {
                  ruleId = getCompiledRuleId(
                    externalIncludedRule,
                    helper,
                    externalGrammar.repository,
                  );
                }
              }
          }
        } else {
          ruleId = getCompiledRuleId(pattern, helper, repository);
        }

        if (ruleId != -1) {
          final rule = helper.getRule(ruleId);
          var skipRule = false;

          if (rule is IncludeOnlyRule ||
              rule is BeginEndRule ||
              rule is BeginWhileRule) {
            final hasMissingPatterns = switch (rule) {
              IncludeOnlyRule() => rule.hasMissingPatterns,
              BeginEndRule() => rule.hasMissingPatterns,
              BeginWhileRule() => rule.hasMissingPatterns,
              _ => false,
            };
            final patternsLength = switch (rule) {
              IncludeOnlyRule() => rule.patterns.length,
              BeginEndRule() => rule.patterns.length,
              BeginWhileRule() => rule.patterns.length,
              _ => 0,
            };
            if (hasMissingPatterns && patternsLength == 0) {
              skipRule = true;
            }
          }

          if (!skipRule) {
            result.add(ruleId);
          }
        }
      }
    }

    return CompilePatternsResult(
      patterns: result,
      hasMissingPatterns: (patterns?.length ?? 0) != result.length,
    );
  }
}

class RegExpSourceAnchorCache {
  const RegExpSourceAnchorCache({
    required this.a0g0,
    required this.a0g1,
    required this.a1g0,
    required this.a1g1,
  });

  final String a0g0;
  final String a0g1;
  final String a1g0;
  final String a1g1;
}

class RegExpSource<TRuleId> {
  RegExpSource(String regExpSource, this.ruleId)
    : source = _normalizeSource(regExpSource),
      hasAnchor = _computeHasAnchor(regExpSource),
      hasBackReferences = _hasBackReferences.hasMatch(
        _normalizeSource(regExpSource),
      ) {
    _anchorCache = hasAnchor ? _buildAnchorCache() : null;
  }

  String source;
  final TRuleId ruleId;
  bool hasAnchor;
  final bool hasBackReferences;
  RegExpSourceAnchorCache? _anchorCache;

  static String _normalizeSource(String regExpSource) {
    if (regExpSource.isEmpty) {
      return regExpSource;
    }

    final output = <String>[];
    var lastPushedPos = 0;
    for (var pos = 0; pos < regExpSource.length; pos++) {
      final ch = regExpSource[pos];
      if (ch == r'\') {
        if (pos + 1 < regExpSource.length) {
          final nextCh = regExpSource[pos + 1];
          if (nextCh == 'z') {
            output.add(regExpSource.substring(lastPushedPos, pos));
            output.add(r'$(?!\n)(?<!\n)');
            lastPushedPos = pos + 2;
          }
          pos++;
        }
      }
    }
    if (lastPushedPos == 0) {
      return regExpSource;
    }
    output.add(regExpSource.substring(lastPushedPos));
    return output.join();
  }

  static bool _computeHasAnchor(String regExpSource) {
    for (var pos = 0; pos < regExpSource.length; pos++) {
      final ch = regExpSource[pos];
      if (ch == r'\' && pos + 1 < regExpSource.length) {
        final nextCh = regExpSource[pos + 1];
        if (nextCh == 'A' || nextCh == 'G') {
          return true;
        }
        pos++;
      }
    }
    return false;
  }

  RegExpSource<TRuleId> clone() => RegExpSource(source, ruleId);

  void setSource(String newSource) {
    if (source == newSource) {
      return;
    }
    source = newSource;
    if (hasAnchor) {
      _anchorCache = _buildAnchorCache();
    }
  }

  String resolveBackReferences(
    String lineText,
    List<OnigCaptureIndex> captureIndices,
  ) {
    return source.replaceAllMapped(_backReferencingEnd, (match) {
      final index = int.parse(match.group(1)!);
      if (index < 0 || index >= captureIndices.length) {
        return '';
      }
      final capture = captureIndices[index];
      return escapeRegExpCharacters(
        lineText.substring(capture.start, capture.end),
      );
    });
  }

  RegExpSourceAnchorCache _buildAnchorCache() {
    final a0g0 = List<String>.filled(source.length, '');
    final a0g1 = List<String>.filled(source.length, '');
    final a1g0 = List<String>.filled(source.length, '');
    final a1g1 = List<String>.filled(source.length, '');

    for (var pos = 0; pos < source.length; pos++) {
      final ch = source[pos];
      a0g0[pos] = ch;
      a0g1[pos] = ch;
      a1g0[pos] = ch;
      a1g1[pos] = ch;

      if (ch == r'\' && pos + 1 < source.length) {
        final nextCh = source[pos + 1];
        if (nextCh == 'A') {
          a0g0[pos + 1] = '\uFFFF';
          a0g1[pos + 1] = '\uFFFF';
          a1g0[pos + 1] = 'A';
          a1g1[pos + 1] = 'A';
        } else if (nextCh == 'G') {
          a0g0[pos + 1] = '\uFFFF';
          a0g1[pos + 1] = 'G';
          a1g0[pos + 1] = '\uFFFF';
          a1g1[pos + 1] = 'G';
        } else {
          a0g0[pos + 1] = nextCh;
          a0g1[pos + 1] = nextCh;
          a1g0[pos + 1] = nextCh;
          a1g1[pos + 1] = nextCh;
        }
        pos++;
      }
    }

    return RegExpSourceAnchorCache(
      a0g0: a0g0.join(),
      a0g1: a0g1.join(),
      a1g0: a1g0.join(),
      a1g1: a1g1.join(),
    );
  }

  String resolveAnchors(bool allowA, bool allowG) {
    if (!hasAnchor || _anchorCache == null) {
      return source;
    }
    if (allowA) {
      return allowG ? _anchorCache!.a1g1 : _anchorCache!.a1g0;
    }
    return allowG ? _anchorCache!.a0g1 : _anchorCache!.a0g0;
  }
}

class RegExpSourceListAnchorCache<TRuleId> {
  CompiledRule<TRuleId>? a0g0;
  CompiledRule<TRuleId>? a0g1;
  CompiledRule<TRuleId>? a1g0;
  CompiledRule<TRuleId>? a1g1;
}

class RegExpSourceList<TRuleId> {
  final List<RegExpSource<TRuleId>> _items = <RegExpSource<TRuleId>>[];
  bool _hasAnchors = false;
  CompiledRule<TRuleId>? _cached;
  final RegExpSourceListAnchorCache<TRuleId> _anchorCache =
      RegExpSourceListAnchorCache<TRuleId>();

  void dispose() {
    _cached?.dispose();
    _cached = null;
    _anchorCache.a0g0?.dispose();
    _anchorCache.a0g0 = null;
    _anchorCache.a0g1?.dispose();
    _anchorCache.a0g1 = null;
    _anchorCache.a1g0?.dispose();
    _anchorCache.a1g0 = null;
    _anchorCache.a1g1?.dispose();
    _anchorCache.a1g1 = null;
  }

  void push(RegExpSource<TRuleId> item) {
    _items.add(item);
    _hasAnchors = _hasAnchors || item.hasAnchor;
  }

  void unshift(RegExpSource<TRuleId> item) {
    _items.insert(0, item);
    _hasAnchors = _hasAnchors || item.hasAnchor;
  }

  int length() => _items.length;

  void setSource(int index, String newSource) {
    if (_items[index].source != newSource) {
      dispose();
      _items[index].setSource(newSource);
    }
  }

  CompiledRule<TRuleId> compile(OnigLib onigLib) {
    _cached ??= CompiledRule<TRuleId>(
      onigLib,
      _items.map((entry) => entry.source).toList(growable: false),
      _items.map((entry) => entry.ruleId).toList(growable: false),
    );
    return _cached!;
  }

  CompiledRule<TRuleId> compileAG(OnigLib onigLib, bool allowA, bool allowG) {
    if (!_hasAnchors) {
      return compile(onigLib);
    }
    if (allowA && allowG) {
      _anchorCache.a1g1 ??= _resolveAnchors(onigLib, allowA, allowG);
      return _anchorCache.a1g1!;
    }
    if (allowA) {
      _anchorCache.a1g0 ??= _resolveAnchors(onigLib, allowA, allowG);
      return _anchorCache.a1g0!;
    }
    if (allowG) {
      _anchorCache.a0g1 ??= _resolveAnchors(onigLib, allowA, allowG);
      return _anchorCache.a0g1!;
    }
    _anchorCache.a0g0 ??= _resolveAnchors(onigLib, allowA, allowG);
    return _anchorCache.a0g0!;
  }

  CompiledRule<TRuleId> _resolveAnchors(
    OnigLib onigLib,
    bool allowA,
    bool allowG,
  ) {
    return CompiledRule<TRuleId>(
      onigLib,
      _items
          .map((entry) => entry.resolveAnchors(allowA, allowG))
          .toList(growable: false),
      _items.map((entry) => entry.ruleId).toList(growable: false),
    );
  }
}

class CompiledRule<TRuleId> {
  CompiledRule(OnigLib onigLib, this.regExps, this.rules)
    : _scanner = onigLib.createOnigScanner(regExps);

  final List<String> regExps;
  final List<TRuleId> rules;
  final OnigScanner _scanner;

  void dispose() {
    _scanner.dispose();
  }

  @override
  String toString() {
    final lines = <String>[];
    for (var i = 0; i < rules.length; i++) {
      lines.add('   - ${rules[i]}: ${regExps[i]}');
    }
    return lines.join('\n');
  }

  FindNextMatchResult<TRuleId>? findNextMatchSync(
    StringOrOnigString string,
    int startPosition,
    int options,
  ) {
    final result = _scanner.findNextMatchSync(string, startPosition, options);
    if (result == null) {
      return null;
    }
    return FindNextMatchResult(
      ruleId: rules[result.index],
      captureIndices: result.captureIndices,
    );
  }
}

class FindNextMatchResult<TRuleId> {
  const FindNextMatchResult({
    required this.ruleId,
    required this.captureIndices,
  });

  final TRuleId ruleId;
  final List<OnigCaptureIndex> captureIndices;
}

typedef IFindNextMatchResult<TRuleId> = FindNextMatchResult<TRuleId>;
