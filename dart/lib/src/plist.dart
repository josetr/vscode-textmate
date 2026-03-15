Object? parsePLIST(String content) {
  return _parse(content, null, null);
}

Object? parseWithLocation(
  String content,
  String? filename,
  String? locationKeyName,
) {
  return _parse(content, filename, locationKeyName);
}

Object? _parse(String content, String? filename, String? locationKeyName) {
  final len = content.length;
  var pos = 0;
  var line = 1;
  var char = 0;

  if (len > 0 && content.codeUnitAt(0) == 65279) {
    pos = 1;
  }

  void advancePosBy(int by) {
    if (locationKeyName == null) {
      pos += by;
      return;
    }
    while (by > 0) {
      final chCode = content.codeUnitAt(pos);
      if (chCode == 10) {
        pos++;
        line++;
        char = 0;
      } else {
        pos++;
        char++;
      }
      by--;
    }
  }

  void advancePosTo(int to) {
    if (locationKeyName == null) {
      pos = to;
      return;
    }
    advancePosBy(to - pos);
  }

  void skipWhitespace() {
    while (pos < len) {
      final chCode = content.codeUnitAt(pos);
      if (chCode != 32 && chCode != 9 && chCode != 13 && chCode != 10) {
        break;
      }
      advancePosBy(1);
    }
  }

  bool advanceIfStartsWith(String value) {
    if (content.substring(pos).startsWith(value)) {
      advancePosBy(value.length);
      return true;
    }
    return false;
  }

  void advanceUntil(String value) {
    final nextOccurrence = content.indexOf(value, pos);
    if (nextOccurrence != -1) {
      advancePosTo(nextOccurrence + value.length);
      return;
    }
    advancePosTo(len);
  }

  String captureUntil(String value) {
    final nextOccurrence = content.indexOf(value, pos);
    if (nextOccurrence != -1) {
      final result = content.substring(pos, nextOccurrence);
      advancePosTo(nextOccurrence + value.length);
      return result;
    }
    final result = content.substring(pos);
    advancePosTo(len);
    return result;
  }

  var state = _State.rootState;
  Object? current;
  final stateStack = <_State>[];
  final objectStack = <Object?>[];
  String? currentKey;

  Never fail(String message) {
    throw StateError(
      'Near offset $pos: $message ~~~${content.substring(pos)}~~~',
    );
  }

  void pushState(_State newState, Object? newCurrent) {
    stateStack.add(state);
    objectStack.add(current);
    state = newState;
    current = newCurrent;
  }

  void popState() {
    if (stateStack.isEmpty) {
      fail('illegal state stack');
    }
    state = stateStack.removeLast();
    current = objectStack.removeLast();
  }

  Map<String, Object?> locationMap() {
    return <String, Object?>{'filename': filename, 'line': line, 'char': char};
  }

  void enterDict() {
    if (state == _State.dictState) {
      if (currentKey == null) {
        fail('missing <key>');
      }
      final newDict = <String, Object?>{};
      if (locationKeyName != null) {
        newDict[locationKeyName] = locationMap();
      }
      (current! as Map<String, Object?>)[currentKey!] = newDict;
      currentKey = null;
      pushState(_State.dictState, newDict);
      return;
    }
    if (state == _State.arrState) {
      final newDict = <String, Object?>{};
      if (locationKeyName != null) {
        newDict[locationKeyName] = locationMap();
      }
      (current! as List<Object?>).add(newDict);
      pushState(_State.dictState, newDict);
      return;
    }
    current = <String, Object?>{};
    if (locationKeyName != null) {
      (current! as Map<String, Object?>)[locationKeyName] = locationMap();
    }
    pushState(_State.dictState, current);
  }

  void leaveDict() {
    if (state != _State.dictState) {
      fail('unexpected </dict>');
    }
    popState();
  }

  void enterArray() {
    if (state == _State.dictState) {
      if (currentKey == null) {
        fail('missing <key>');
      }
      final newArray = <Object?>[];
      (current! as Map<String, Object?>)[currentKey!] = newArray;
      currentKey = null;
      pushState(_State.arrState, newArray);
      return;
    }
    if (state == _State.arrState) {
      final newArray = <Object?>[];
      (current! as List<Object?>).add(newArray);
      pushState(_State.arrState, newArray);
      return;
    }
    current = <Object?>[];
    pushState(_State.arrState, current);
  }

  void leaveArray() {
    if (state != _State.arrState) {
      fail('unexpected </array>');
    }
    popState();
  }

  void acceptKey(String value) {
    if (state != _State.dictState) {
      fail('unexpected <key>');
    }
    if (currentKey != null) {
      fail('too many <key>');
    }
    currentKey = value;
  }

  void acceptValue(Object? value) {
    if (state == _State.dictState) {
      if (currentKey == null) {
        fail('missing <key>');
      }
      (current! as Map<String, Object?>)[currentKey!] = value;
      currentKey = null;
      return;
    }
    if (state == _State.arrState) {
      (current! as List<Object?>).add(value);
      return;
    }
    current = value;
  }

  String escapeValue(String value) {
    return value
        .replaceAllMapped(RegExp(r'&#([0-9]+);'), (match) {
          return String.fromCharCode(int.parse(match.group(1)!));
        })
        .replaceAllMapped(RegExp(r'&#x([0-9a-f]+);', caseSensitive: false), (
          match,
        ) {
          return String.fromCharCode(int.parse(match.group(1)!, radix: 16));
        })
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  _ParsedTag parseOpenTag() {
    var raw = captureUntil('>');
    var isClosed = false;
    if (raw.isNotEmpty && raw.codeUnitAt(raw.length - 1) == 47) {
      isClosed = true;
      raw = raw.substring(0, raw.length - 1);
    }
    return _ParsedTag(raw.trim(), isClosed);
  }

  String parseTagValue(_ParsedTag tag) {
    if (tag.isClosed) {
      return '';
    }
    final value = captureUntil('</');
    advanceUntil('>');
    return escapeValue(value);
  }

  while (pos < len) {
    skipWhitespace();
    if (pos >= len) {
      break;
    }

    final chCode = content.codeUnitAt(pos);
    advancePosBy(1);
    if (chCode != 60) {
      fail('expected <');
    }
    if (pos >= len) {
      fail('unexpected end of input');
    }

    final peekChCode = content.codeUnitAt(pos);
    if (peekChCode == 63) {
      advancePosBy(1);
      advanceUntil('?>');
      continue;
    }
    if (peekChCode == 33) {
      advancePosBy(1);
      if (advanceIfStartsWith('--')) {
        advanceUntil('-->');
        continue;
      }
      advanceUntil('>');
      continue;
    }
    if (peekChCode == 47) {
      advancePosBy(1);
      skipWhitespace();
      if (advanceIfStartsWith('plist')) {
        advanceUntil('>');
        continue;
      }
      if (advanceIfStartsWith('dict')) {
        advanceUntil('>');
        leaveDict();
        continue;
      }
      if (advanceIfStartsWith('array')) {
        advanceUntil('>');
        leaveArray();
        continue;
      }
      fail('unexpected closed tag');
    }

    final tag = parseOpenTag();
    switch (tag.name) {
      case 'dict':
        enterDict();
        if (tag.isClosed) {
          leaveDict();
        }
        continue;
      case 'array':
        enterArray();
        if (tag.isClosed) {
          leaveArray();
        }
        continue;
      case 'key':
        acceptKey(parseTagValue(tag));
        continue;
      case 'string':
        acceptValue(parseTagValue(tag));
        continue;
      case 'real':
        acceptValue(double.parse(parseTagValue(tag)));
        continue;
      case 'integer':
        acceptValue(int.parse(parseTagValue(tag)));
        continue;
      case 'date':
        acceptValue(DateTime.parse(parseTagValue(tag)));
        continue;
      case 'data':
        acceptValue(parseTagValue(tag));
        continue;
      case 'true':
        parseTagValue(tag);
        acceptValue(true);
        continue;
      case 'false':
        parseTagValue(tag);
        acceptValue(false);
        continue;
      default:
        if (RegExp(r'^plist').hasMatch(tag.name)) {
          continue;
        }
        fail('unexpected opened tag ${tag.name}');
    }
  }

  return current;
}

enum _State { rootState, dictState, arrState }

class _ParsedTag {
  const _ParsedTag(this.name, this.isClosed);

  final String name;
  final bool isClosed;
}
