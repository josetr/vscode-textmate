import 'package:vscode_textmate/src/onigLib.dart';

T clone<T>(T something) => _doClone(something) as T;

Object? _doClone(Object? something) {
  if (something is List) {
    return something.map(_doClone).toList(growable: true);
  }
  if (something is Map) {
    return {
      for (final entry in something.entries) entry.key: _doClone(entry.value),
    };
  }
  return something;
}

Map<String, Object?> mergeObjects(
  Map<String, Object?> target,
  List<Map<String, Object?>> sources,
) {
  for (final source in sources) {
    target.addAll(source);
  }
  return target;
}

String basename(String path) {
  final idx = path.lastIndexOf(RegExp(r'[/\\]'));
  if (idx == -1) {
    return path;
  }
  if (idx == path.length - 1) {
    return basename(path.substring(0, path.length - 1));
  }
  return path.substring(idx + 1);
}

final RegExp _capturingRegexSource = RegExp(
  r'\$(\d+)|\${(\d+):\/(downcase|upcase)}',
);

class RegexSource {
  static bool hasCaptures(String? regexSource) {
    if (regexSource == null) {
      return false;
    }
    return _capturingRegexSource.hasMatch(regexSource);
  }

  static String replaceCaptures(
    String regexSource,
    String captureSource,
    List<OnigCaptureIndex> captureIndices,
  ) {
    return regexSource.replaceAllMapped(_capturingRegexSource, (match) {
      final index = match.group(1) ?? match.group(2);
      final command = match.group(3);
      if (index == null) {
        return match.group(0)!;
      }
      final capture = captureIndices[int.parse(index)];
      var result = captureSource.substring(capture.start, capture.end);
      while (result.isNotEmpty && result[0] == '.') {
        result = result.substring(1);
      }
      switch (command) {
        case 'downcase':
          return result.toLowerCase();
        case 'upcase':
          return result.toUpperCase();
        default:
          return result;
      }
    });
  }
}

int strcmp(String a, String b) {
  return a.compareTo(b);
}

int strArrCmp(List<String>? a, List<String>? b) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return -1;
  }
  if (b == null) {
    return 1;
  }
  if (a.length == b.length) {
    for (var i = 0; i < a.length; i++) {
      final result = strcmp(a[i], b[i]);
      if (result != 0) {
        return result;
      }
    }
    return 0;
  }
  return a.length - b.length;
}

bool isValidHexColor(String hex) {
  return RegExp(r'^#[0-9a-f]{6}$', caseSensitive: false).hasMatch(hex) ||
      RegExp(r'^#[0-9a-f]{8}$', caseSensitive: false).hasMatch(hex) ||
      RegExp(r'^#[0-9a-f]{3}$', caseSensitive: false).hasMatch(hex) ||
      RegExp(r'^#[0-9a-f]{4}$', caseSensitive: false).hasMatch(hex);
}

String escapeRegExpCharacters(String value) {
  return value.replaceAllMapped(
    RegExp(r'[\\|([{}\]).?*+^$]'),
    (match) => '\\${match.group(0)}',
  );
}

class CachedFn<TKey, TValue> {
  CachedFn(this._fn);

  final TValue Function(TKey key) _fn;
  final Map<TKey, TValue> _cache = <TKey, TValue>{};

  TValue get(TKey key) => _cache.putIfAbsent(key, () => _fn(key));
}

int performanceNow() => DateTime.now().millisecondsSinceEpoch;

RegExp? _containsRtl;

bool containsRTL(String value) {
  _containsRtl ??= RegExp(
    r'(?:[\u05BE\u05C0\u05C3\u05C6\u05D0-\u05F4\u0608\u060B\u060D\u061B-\u064A\u066D-\u066F\u0671-\u06D5\u06E5\u06E6\u06EE\u06EF\u06FA-\u0710\u0712-\u072F\u074D-\u07A5\u07B1-\u07EA\u07F4\u07F5\u07FA\u07FE-\u0815\u081A\u0824\u0828\u0830-\u0858\u085E-\u088E\u08A0-\u08C9\u200F\uFB1D\uFB1F-\uFB28\uFB2A-\uFD3D\uFD50-\uFDC7\uFDF0-\uFDFC\uFE70-\uFEFC]|\uD802[\uDC00-\uDD1B\uDD20-\uDE00\uDE10-\uDE35\uDE40-\uDEE4\uDEEB-\uDF35\uDF40-\uDFFF]|\uD803[\uDC00-\uDD23\uDE80-\uDEA9\uDEAD-\uDF45\uDF51-\uDF81\uDF86-\uDFF6]|\uD83A[\uDC00-\uDCCF\uDD00-\uDD43\uDD4B-\uDFFF]|\uD83B[\uDC00-\uDEBB])',
  );
  return _containsRtl!.hasMatch(value);
}
