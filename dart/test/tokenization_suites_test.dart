import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vscode_textmate/vscode_textmate.dart';

void main() {
  late Future<OnigLib> onigLib;
  final repositoryRoot = p.normalize(p.join(Directory.current.path, '..'));

  setUpAll(() async {
    onigLib = loadOnigWasm(
      wasmPath: p.join(
        repositoryRoot,
        'node_modules',
        'vscode-oniguruma',
        'release',
        'onig.wasm',
      ),
    );
  });

  Future<void> expectSuitePasses(String relativePath) async {
    final suiteLocation = p.join(repositoryRoot, relativePath);
    final suiteDirectory = p.dirname(suiteLocation);
    final tests =
        (jsonDecode(File(suiteLocation).readAsStringSync()) as List<Object?>)
            .cast<Map<Object?, Object?>>();
    final failures = <String>[];

    for (final testCase in tests) {
      String? grammarScopeName = testCase['grammarScopeName'] as String?;
      final grammarByScope = <String, RawGrammar>{};

      for (final grammarPath
          in (testCase['grammars'] as List<Object?>).cast<String>()) {
        final absoluteGrammarPath = p.join(suiteDirectory, grammarPath);
        final content = File(absoluteGrammarPath).readAsStringSync();
        final rawGrammar = parseRawGrammar(content, absoluteGrammarPath);
        grammarByScope[rawGrammar.scopeName] = rawGrammar;
        if (grammarScopeName == null &&
            grammarPath == testCase['grammarPath']) {
          grammarScopeName = rawGrammar.scopeName;
        }
      }

      if (grammarScopeName == null) {
        failures.add('No grammar for test ${testCase['desc']}');
        continue;
      }

      final registry = Registry(
        RegistryOptions(
          onigLib: onigLib,
          loadGrammar: (scopeName) async => grammarByScope[scopeName],
          getInjections: (scopeName) {
            if (scopeName == grammarScopeName) {
              return (testCase['grammarInjections'] as List<Object?>?)
                  ?.cast<String>();
            }
            return null;
          },
        ),
      );

      try {
        final grammar = await registry.loadGrammar(grammarScopeName);
        if (grammar == null) {
          failures.add('Could not load grammar $grammarScopeName');
          continue;
        }

        StateStack? prevState;
        for (final lineCase
            in (testCase['lines'] as List<Object?>)
                .cast<Map<Object?, Object?>>()) {
          var actual = grammar.tokenizeLine(
            lineCase['line'] as String,
            prevState,
          );
          final lineText = lineCase['line'] as String;
          final actualTokens = actual.tokens
              .map(
                (token) => <String, Object>{
                  'value': lineText.substring(
                    token.startIndex.clamp(0, lineText.length),
                    token.endIndex.clamp(0, lineText.length),
                  ),
                  'scopes': token.scopes,
                },
              )
              .toList(growable: false);

          var expectedTokens = (lineCase['tokens'] as List<Object?>)
              .cast<Map<Object?, Object?>>();
          if (lineText.isNotEmpty) {
            expectedTokens = expectedTokens
                .where((token) => (token['value'] as String).isNotEmpty)
                .toList(growable: false);
          }

          final normalizedExpected = expectedTokens
              .map(
                (token) => <String, Object>{
                  'value': token['value'] as String,
                  'scopes': (token['scopes'] as List<Object?>).cast<String>(),
                },
              )
              .toList(growable: false);

          if (actualTokens.toString() != normalizedExpected.toString()) {
            failures.add(
              '${testCase['desc']}\nline: $lineText\nexpected: $normalizedExpected\nactual: $actualTokens',
            );
            break;
          }

          if (prevState != null) {
            final diff = diffStateStacksRefEq(prevState, actual.ruleStack);
            actual = TokenizeLineResult(
              tokens: actual.tokens,
              fonts: actual.fonts,
              ruleStack: applyStateStackDiff(prevState, diff)!,
              stoppedEarly: actual.stoppedEarly,
            );
          }
          prevState = actual.ruleStack;
        }
      } finally {
        registry.dispose();
      }
    }

    expect(
      failures.length,
      0,
      reason: failures.isEmpty ? null : failures.join('\n\n'),
    );
  }

  test('first-mate fixture suite passes', () async {
    await expectSuitePasses('test-cases/first-mate/tests.json');
  });

  test('suite1 fixture suite passes', () async {
    await expectSuitePasses('test-cases/suite1/tests.json');
  });

  test('suite1 while fixture suite passes', () async {
    await expectSuitePasses('test-cases/suite1/whileTests.json');
  });
}
