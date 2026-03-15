import 'package:test/test.dart';
import 'package:vscode_textmate/vscode_textmate.dart';

void main() {
  test('State stack diff can reconstruct target stack', () {
    final common = StateStackImpl.nullStack.push(
      1,
      0,
      0,
      false,
      null,
      null,
      null,
    );
    final first = common.push(2, 1, 1, false, 'end.2', null, null);
    final second = common.push(3, 2, 2, true, 'end.3', null, null);

    final diff = diffStateStacksRefEq(first, second);
    final rebuilt = applyStateStackDiff(first, diff);

    expect(diff.pops, 1);
    expect(diff.newFrames, hasLength(1));
    expect(rebuilt!.equals(second), isTrue);
    expect(rebuilt.toStateStackFrame().ruleId, 3);
    expect(rebuilt.toStateStackFrame().endRule, 'end.3');
  });

  test('Balanced bracket selectors include and exclude scopes', () {
    final selectors = BalancedBracketSelectors(
      <String>['meta.brace', '*'],
      <String>['string.quoted'],
    );

    expect(selectors.matchesAlways, isFalse);
    expect(selectors.match(<String>['source.test', 'meta.brace']), isTrue);
    expect(selectors.match(<String>['source.test']), isTrue);
    expect(selectors.match(<String>['source.test', 'string.quoted']), isFalse);
  });
}
