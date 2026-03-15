import 'dart:convert';

import 'rawGrammar.dart';

Object? parseJSON(String source, String? filename, bool withMetadata) {
  final streamState = _JSONStreamState(source);
  final token = _JSONToken();
  var state = _JSONState.rootState;
  Object? current;
  final stateStack = <_JSONState>[];
  final objectStack = <Object?>[];

  void pushState() {
    stateStack.add(state);
    objectStack.add(current);
  }

  void popState() {
    state = stateStack.removeLast();
    current = objectStack.removeLast();
  }

  void fail(String message) {
    throw StateError(
      'Near offset ${streamState.pos}: $message '
      '~~~${streamState.source.substring(streamState.pos)}~~~',
    );
  }

  while (_nextJSONToken(streamState, token)) {
    if (state == _JSONState.rootState) {
      if (current != null) {
        fail('too many constructs in root');
      }

      if (token.type == _JSONTokenType.leftCurlyBracket) {
        current = <String, Object?>{};
        if (withMetadata) {
          (current as Map<String, Object?>)['\$vscodeTextmateLocation'] = token
              .toLocation(filename);
        }
        pushState();
        state = _JSONState.dictState;
        continue;
      }

      if (token.type == _JSONTokenType.leftSquareBracket) {
        current = <Object?>[];
        pushState();
        state = _JSONState.arrState;
        continue;
      }

      fail('unexpected token in root');
    }

    if (state == _JSONState.dictStateComma) {
      if (token.type == _JSONTokenType.rightCurlyBracket) {
        popState();
        continue;
      }
      if (token.type == _JSONTokenType.comma) {
        state = _JSONState.dictStateNoClose;
        continue;
      }
      fail('expected , or }');
    }

    if (state == _JSONState.dictState || state == _JSONState.dictStateNoClose) {
      if (state == _JSONState.dictState &&
          token.type == _JSONTokenType.rightCurlyBracket) {
        popState();
        continue;
      }

      if (token.type == _JSONTokenType.string) {
        final keyValue = token.value!;
        if (!_nextJSONToken(streamState, token) ||
            token.type != _JSONTokenType.colon) {
          fail('expected colon');
        }
        if (!_nextJSONToken(streamState, token)) {
          fail('expected value');
        }

        state = _JSONState.dictStateComma;
        final currentMap = current! as Map<String, Object?>;

        switch (token.type) {
          case _JSONTokenType.string:
            currentMap[keyValue] = token.value;
            continue;
          case _JSONTokenType.nullValue:
            currentMap[keyValue] = null;
            continue;
          case _JSONTokenType.trueValue:
            currentMap[keyValue] = true;
            continue;
          case _JSONTokenType.falseValue:
            currentMap[keyValue] = false;
            continue;
          case _JSONTokenType.number:
            currentMap[keyValue] = double.parse(token.value!);
            continue;
          case _JSONTokenType.leftSquareBracket:
            final newArr = <Object?>[];
            currentMap[keyValue] = newArr;
            pushState();
            state = _JSONState.arrState;
            current = newArr;
            continue;
          case _JSONTokenType.leftCurlyBracket:
            final newDict = <String, Object?>{};
            if (withMetadata) {
              newDict['\$vscodeTextmateLocation'] = token.toLocation(filename);
            }
            currentMap[keyValue] = newDict;
            pushState();
            state = _JSONState.dictState;
            current = newDict;
            continue;
          default:
            break;
        }
      }

      fail('unexpected token in dict');
    }

    if (state == _JSONState.arrStateComma) {
      if (token.type == _JSONTokenType.rightSquareBracket) {
        popState();
        continue;
      }
      if (token.type == _JSONTokenType.comma) {
        state = _JSONState.arrStateNoClose;
        continue;
      }
      fail('expected , or ]');
    }

    if (state == _JSONState.arrState || state == _JSONState.arrStateNoClose) {
      if (state == _JSONState.arrState &&
          token.type == _JSONTokenType.rightSquareBracket) {
        popState();
        continue;
      }

      state = _JSONState.arrStateComma;
      final currentList = current! as List<Object?>;

      switch (token.type) {
        case _JSONTokenType.string:
          currentList.add(token.value);
          continue;
        case _JSONTokenType.nullValue:
          currentList.add(null);
          continue;
        case _JSONTokenType.trueValue:
          currentList.add(true);
          continue;
        case _JSONTokenType.falseValue:
          currentList.add(false);
          continue;
        case _JSONTokenType.number:
          currentList.add(double.parse(token.value!));
          continue;
        case _JSONTokenType.leftSquareBracket:
          final newArr = <Object?>[];
          currentList.add(newArr);
          pushState();
          state = _JSONState.arrState;
          current = newArr;
          continue;
        case _JSONTokenType.leftCurlyBracket:
          final newDict = <String, Object?>{};
          if (withMetadata) {
            newDict['\$vscodeTextmateLocation'] = token.toLocation(filename);
          }
          currentList.add(newDict);
          pushState();
          state = _JSONState.dictState;
          current = newDict;
          continue;
        default:
          break;
      }

      fail('unexpected token in array');
    }

    fail('unknown state');
  }

  if (objectStack.isNotEmpty) {
    fail('unclosed constructs');
  }

  return current;
}

enum _JSONState {
  rootState,
  dictState,
  dictStateComma,
  dictStateNoClose,
  arrState,
  arrStateComma,
  arrStateNoClose,
}

enum _JSONTokenType {
  unknown,
  string,
  leftSquareBracket,
  leftCurlyBracket,
  rightSquareBracket,
  rightCurlyBracket,
  colon,
  comma,
  nullValue,
  trueValue,
  falseValue,
  number,
}

class _JSONStreamState {
  _JSONStreamState(this.source);

  final String source;
  int pos = 0;
  int line = 1;
  int char = 0;

  int get len => source.length;
}

class _JSONToken {
  String? value;
  _JSONTokenType type = _JSONTokenType.unknown;
  int offset = -1;
  int len = -1;
  int line = -1;
  int char = -1;

  Location toLocation(String? filename) {
    return Location(filename: filename, line: line, char: char);
  }
}

bool _nextJSONToken(_JSONStreamState state, _JSONToken out) {
  out
    ..value = null
    ..type = _JSONTokenType.unknown
    ..offset = -1
    ..len = -1
    ..line = -1
    ..char = -1;

  final source = state.source;
  var pos = state.pos;
  var line = state.line;
  var char = state.char;

  while (true) {
    if (pos >= state.len) {
      return false;
    }
    final ch = source.codeUnitAt(pos);
    if (ch == 0x20 || ch == 0x09 || ch == 0x0d) {
      pos++;
      char++;
      continue;
    }
    if (ch == 0x0a) {
      pos++;
      line++;
      char = 0;
      continue;
    }
    break;
  }

  out
    ..offset = pos
    ..line = line
    ..char = char;

  var chCode = source.codeUnitAt(pos);

  if (chCode == 0x22) {
    out.type = _JSONTokenType.string;
    pos++;
    char++;
    while (true) {
      if (pos >= state.len) {
        return false;
      }
      chCode = source.codeUnitAt(pos);
      pos++;
      char++;
      if (chCode == 0x5c) {
        pos++;
        char++;
        continue;
      }
      if (chCode == 0x22) {
        break;
      }
    }
    out.value = jsonDecode(source.substring(out.offset, pos)) as String;
  } else if (chCode == 0x5b) {
    out.type = _JSONTokenType.leftSquareBracket;
    pos++;
    char++;
  } else if (chCode == 0x7b) {
    out.type = _JSONTokenType.leftCurlyBracket;
    pos++;
    char++;
  } else if (chCode == 0x5d) {
    out.type = _JSONTokenType.rightSquareBracket;
    pos++;
    char++;
  } else if (chCode == 0x7d) {
    out.type = _JSONTokenType.rightCurlyBracket;
    pos++;
    char++;
  } else if (chCode == 0x3a) {
    out.type = _JSONTokenType.colon;
    pos++;
    char++;
  } else if (chCode == 0x2c) {
    out.type = _JSONTokenType.comma;
    pos++;
    char++;
  } else if (source.startsWith('null', pos)) {
    out.type = _JSONTokenType.nullValue;
    pos += 4;
    char += 4;
  } else if (source.startsWith('true', pos)) {
    out.type = _JSONTokenType.trueValue;
    pos += 4;
    char += 4;
  } else if (source.startsWith('false', pos)) {
    out.type = _JSONTokenType.falseValue;
    pos += 5;
    char += 5;
  } else {
    out.type = _JSONTokenType.number;
    while (pos < state.len) {
      chCode = source.codeUnitAt(pos);
      final isNumberChar =
          chCode == 0x2e ||
          (chCode >= 0x30 && chCode <= 0x39) ||
          chCode == 0x65 ||
          chCode == 0x45 ||
          chCode == 0x2d ||
          chCode == 0x2b;
      if (!isNumberChar) {
        break;
      }
      pos++;
      char++;
    }
  }

  out.len = pos - out.offset;
  out.value ??= source.substring(out.offset, pos);
  state
    ..pos = pos
    ..line = line
    ..char = char;
  return true;
}
