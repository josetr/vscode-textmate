import 'debug.dart';
import 'json.dart';
import 'plist.dart';
import 'rawGrammar.dart';

RawGrammar parseRawGrammar(String content, [String? filePath]) {
  if (filePath != null && filePath.endsWith('.json')) {
    return _parseJsonGrammar(content, filePath);
  }
  return _parsePlistGrammar(content, filePath);
}

RawGrammar _parseJsonGrammar(String content, String? filename) {
  if (DebugFlags.inDebugMode) {
    return RawGrammar.fromMap(
      parseJSON(content, filename, true) as Map<Object?, Object?>,
    );
  }
  return RawGrammar.fromMap(
    parseJSON(content, filename, false) as Map<Object?, Object?>,
  );
}

RawGrammar _parsePlistGrammar(String content, String? filename) {
  if (DebugFlags.inDebugMode) {
    return RawGrammar.fromMap(
      parseWithLocation(content, filename, r'$vscodeTextmateLocation')
          as Map<Object?, Object?>,
    );
  }
  return RawGrammar.fromMap(parsePLIST(content) as Map<Object?, Object?>);
}
