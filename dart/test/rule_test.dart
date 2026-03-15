import 'package:test/test.dart';
import 'package:vscode_textmate/vscode_textmate.dart';

void main() {
  test(r'RegExpSource normalizes \z and resolves anchors', () {
    final source = RegExpSource<int>(r'\Afoo\Gbar\z', 7);

    expect(source.source, r'\Afoo\Gbar$(?!\n)(?<!\n)');
    expect(source.hasAnchor, isTrue);
    expect(source.resolveAnchors(false, false), contains('\uFFFF'));
    expect(source.resolveAnchors(true, false), contains(r'\A'));
    expect(source.resolveAnchors(false, true), contains(r'\G'));
  });

  test('RegExpSource resolves back references', () {
    final source = RegExpSource<int>(r'</\1-\2>', 3);
    final result = source.resolveBackReferences('abc-[]', const [
      OnigCaptureIndex(start: 0, end: 6, length: 6),
      OnigCaptureIndex(start: 0, end: 3, length: 3),
      OnigCaptureIndex(start: 4, end: 6, length: 2),
    ]);

    expect(result, r'</abc-\[\]>');
  });

  test('RuleFactory assigns ids and resolves local includes', () {
    final child = RawRule(match: r'bar', name: 'match.bar');
    final root = RawRule(patterns: <RawRule>[RawRule(include: '#child')]);
    final repository = RawRepository(values: <String, RawRule>{'child': child});
    final helper = _FakeHelper();

    final rootId = RuleFactory.getCompiledRuleId(root, helper, repository);

    expect(root.id, rootId);
    expect(child.id, isNotNull);
    expect(helper.getRule(rootId), isA<IncludeOnlyRule>());
    expect(helper.getRule(child.id!), isA<MatchRule>());

    final rootRule = helper.getRule(rootId) as IncludeOnlyRule;
    expect(rootRule.patterns, [child.id]);
    expect(rootRule.hasMissingPatterns, isFalse);
  });

  test('BeginEndRule updates end pattern back references during compile', () {
    final helper = _FakeHelper();
    final nested = helper.registerRule(
      (id) => MatchRule(null, id, 'nested', r'foo', const []),
    );
    final rule = BeginEndRule(
      null,
      helper.nextRuleId(),
      'wrapper',
      null,
      r'<(\w+)>',
      const [],
      r'</\1>',
      const [],
      false,
      CompilePatternsResult(
        patterns: <RuleId>[nested.id],
        hasMissingPatterns: false,
      ),
    );
    helper.store(rule);

    final compiled = rule.compile(helper, r'</div>');

    expect(compiled.regExps.first, r'</div>');
    expect(compiled.regExps.last, r'foo');
  });
}

class _FakeHelper implements RuleFactoryHelper, OnigRuleRegistry {
  final Map<int, Rule> _rules = <int, Rule>{};
  int _lastRuleId = 0;

  int nextRuleId() => ++_lastRuleId;

  void store(Rule rule) {
    _rules[rule.id] = rule;
  }

  @override
  Rule getRule(RuleId ruleId) => _rules[ruleId]!;

  @override
  RawGrammar? getExternalGrammar(String scopeName, RawRepository repository) {
    return null;
  }

  @override
  T registerRule<T extends Rule>(T Function(RuleId id) factory) {
    final id = nextRuleId();
    final rule = factory(id);
    _rules[id] = rule;
    return rule;
  }

  @override
  OnigScanner createOnigScanner(List<String> sources) {
    return _FakeScanner();
  }

  @override
  OnigString createOnigString(String value) {
    return _FakeString(value);
  }
}

class _FakeScanner implements OnigScanner {
  @override
  void dispose() {}

  @override
  OnigMatch? findNextMatchSync(
    StringOrOnigString string,
    int startPosition,
    int options,
  ) {
    return null;
  }
}

class _FakeString implements OnigString {
  _FakeString(this.content);

  @override
  final String content;

  @override
  void dispose() {}
}
