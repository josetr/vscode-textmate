import 'package:test/test.dart';
import 'package:vscode_textmate/vscode_textmate.dart';

void main() {
  final tests = [
    {
      'expression': 'foo',
      'input': ['foo'],
      'result': true,
    },
    {
      'expression': 'foo',
      'input': ['bar'],
      'result': false,
    },
    {
      'expression': '- foo',
      'input': ['foo'],
      'result': false,
    },
    {
      'expression': '- foo',
      'input': ['bar'],
      'result': true,
    },
    {
      'expression': '- - foo',
      'input': ['bar'],
      'result': false,
    },
    {
      'expression': 'bar foo',
      'input': ['foo'],
      'result': false,
    },
    {
      'expression': 'bar foo',
      'input': ['bar'],
      'result': false,
    },
    {
      'expression': 'bar foo',
      'input': ['bar', 'foo'],
      'result': true,
    },
    {
      'expression': 'bar - foo',
      'input': ['bar'],
      'result': true,
    },
    {
      'expression': 'bar - foo',
      'input': ['foo', 'bar'],
      'result': false,
    },
    {
      'expression': 'bar - foo',
      'input': ['foo'],
      'result': false,
    },
    {
      'expression': 'bar, foo',
      'input': ['foo'],
      'result': true,
    },
    {
      'expression': 'bar, foo',
      'input': ['bar'],
      'result': true,
    },
    {
      'expression': 'bar, foo',
      'input': ['bar', 'foo'],
      'result': true,
    },
  ];

  bool nameMatcher(List<String> identifiers, List<String> stackElements) {
    var lastIndex = 0;
    return identifiers.every((identifier) {
      for (var i = lastIndex; i < stackElements.length; i++) {
        if (stackElements[i] == identifier) {
          lastIndex = i + 1;
          return true;
        }
      }
      return false;
    });
  }

  for (var index = 0; index < tests.length; index++) {
    final tst = tests[index];
    test('Matcher Test #$index', () {
      final matchers = createMatchers<List<String>>(
        tst['expression']! as String,
        nameMatcher,
      );
      final result = matchers.any(
        (matcher) => matcher.matcher(tst['input']! as List<String>),
      );
      expect(result, tst['result']);
    });
  }
}
