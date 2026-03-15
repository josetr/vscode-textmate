import 'package:test/test.dart';
import 'package:vscode_textmate/vscode_textmate.dart';

void main() {
  late OnigLib onigLib;

  setUpAll(() async {
    onigLib = await loadOnigWasm();
  });

  test('matches a simple pattern', () {
    final scanner = onigLib.createOnigScanner(<String>[r'hello']);
    addTearDown(scanner.dispose);

    final match = scanner.findNextMatchSync(
      'well hello there',
      0,
      FindOption.none,
    );
    expect(match, isNotNull);
    expect(match!.index, 0);
    expect(match.captureIndices.first.start, 5);
    expect(match.captureIndices.first.end, 10);
  });

  test('maps utf16 offsets correctly', () {
    final scanner = onigLib.createOnigScanner(<String>[r'😀b']);
    addTearDown(scanner.dispose);

    final match = scanner.findNextMatchSync('a😀b', 0, FindOption.none);
    expect(match, isNotNull);
    expect(match!.captureIndices.first.start, 1);
    expect(match.captureIndices.first.end, 4);
  });
}
