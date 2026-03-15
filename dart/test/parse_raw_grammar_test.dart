import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vscode_textmate/vscode_textmate.dart';

void main() {
  final repoRoot = p.normalize(p.join(Directory.current.path, '..'));

  test('parses JSON grammar fixture', () {
    final file = File(
      p.join(repoRoot, 'test-cases', 'suite1', 'fixtures', 'javascript.json'),
    );
    final grammar = parseRawGrammar(file.readAsStringSync(), file.path);
    expect(grammar.scopeName, 'source.js');
  });

  test('parses PLIST grammar fixture', () {
    final file = File(
      p.join(repoRoot, 'test-cases', 'suite1', 'fixtures', 'Ruby.plist'),
    );
    final grammar = parseRawGrammar(file.readAsStringSync(), file.path);
    expect(grammar.scopeName, 'source.ruby');
  });
}
