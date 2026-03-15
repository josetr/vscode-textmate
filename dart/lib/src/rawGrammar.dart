import 'theme.dart';

class Location {
  const Location({
    required this.filename,
    required this.line,
    required this.char,
  });

  final String? filename;
  final int line;
  final int char;

  factory Location.fromMap(Map<Object?, Object?> map) {
    return Location(
      filename: map['filename'] as String?,
      line: (map['line'] as num).toInt(),
      char: (map['char'] as num).toInt(),
    );
  }
}

class RawRule {
  RawRule({
    this.id,
    this.include,
    this.name,
    this.contentName,
    this.match,
    this.captures,
    this.begin,
    this.beginCaptures,
    this.end,
    this.endCaptures,
    this.whilePattern,
    this.whileCaptures,
    this.patterns,
    this.repository,
    this.applyEndPatternLast,
    this.location,
  });

  int? id;
  final String? include;
  final ScopeName? name;
  final ScopeName? contentName;
  final String? match;
  final Map<String, RawRule>? captures;
  final String? begin;
  final Map<String, RawRule>? beginCaptures;
  final String? end;
  final Map<String, RawRule>? endCaptures;
  final String? whilePattern;
  final Map<String, RawRule>? whileCaptures;
  final List<RawRule>? patterns;
  final RawRepository? repository;
  final bool? applyEndPatternLast;
  final Location? location;

  factory RawRule.fromMap(Map<Object?, Object?> map) {
    Map<String, RawRule>? convertRuleMap(Object? value) {
      if (value is! Map) {
        return null;
      }
      return value.map(
        (key, entry) => MapEntry(
          key as String,
          RawRule.fromMap((entry as Map<Object?, Object?>)),
        ),
      );
    }

    List<RawRule>? convertRuleList(Object? value) {
      if (value is! List) {
        return null;
      }
      return value
          .map((entry) => RawRule.fromMap(entry as Map<Object?, Object?>))
          .toList(growable: false);
    }

    return RawRule(
      id: (map['id'] as num?)?.toInt(),
      include: map['include'] as String?,
      name: map['name'] as ScopeName?,
      contentName: map['contentName'] as ScopeName?,
      match: map['match'] as String?,
      captures: convertRuleMap(map['captures']),
      begin: map['begin'] as String?,
      beginCaptures: convertRuleMap(map['beginCaptures']),
      end: map['end'] as String?,
      endCaptures: convertRuleMap(map['endCaptures']),
      whilePattern: map['while'] as String?,
      whileCaptures: convertRuleMap(map['whileCaptures']),
      patterns: convertRuleList(map['patterns']),
      repository: map['repository'] is Map
          ? RawRepository.fromMap(map['repository'] as Map<Object?, Object?>)
          : null,
      applyEndPatternLast: switch (map['applyEndPatternLast']) {
        bool value => value,
        num value => value != 0,
        _ => null,
      },
      location: map[r'$vscodeTextmateLocation'] is Map
          ? Location.fromMap(
              map[r'$vscodeTextmateLocation'] as Map<Object?, Object?>,
            )
          : null,
    );
  }
}

class RawRepository {
  const RawRepository({required this.values, this.location});

  final Map<String, RawRule> values;
  final Location? location;

  RawRule? operator [](String key) => values[key];

  factory RawRepository.fromMap(Map<Object?, Object?> map) {
    final values = <String, RawRule>{};
    for (final entry in map.entries) {
      final key = entry.key as String;
      if (key == r'$vscodeTextmateLocation') {
        continue;
      }
      values[key] = RawRule.fromMap(entry.value as Map<Object?, Object?>);
    }
    return RawRepository(
      values: values,
      location: map[r'$vscodeTextmateLocation'] is Map
          ? Location.fromMap(
              map[r'$vscodeTextmateLocation'] as Map<Object?, Object?>,
            )
          : null,
    );
  }
}

class RawGrammar {
  const RawGrammar({
    required this.repository,
    required this.scopeName,
    required this.patterns,
    this.injections,
    this.injectionSelector,
    this.fileTypes,
    this.name,
    this.firstLineMatch,
    this.location,
  });

  final RawRepository repository;
  final ScopeName scopeName;
  final List<RawRule> patterns;
  final Map<String, RawRule>? injections;
  final String? injectionSelector;
  final List<String>? fileTypes;
  final String? name;
  final String? firstLineMatch;
  final Location? location;

  factory RawGrammar.fromMap(Map<Object?, Object?> map) {
    Map<String, RawRule>? convertRuleMap(Object? value) {
      if (value is! Map) {
        return null;
      }
      return value.map(
        (key, entry) => MapEntry(
          key as String,
          RawRule.fromMap(entry as Map<Object?, Object?>),
        ),
      );
    }

    return RawGrammar(
      repository: map['repository'] is Map
          ? RawRepository.fromMap(map['repository'] as Map<Object?, Object?>)
          : const RawRepository(values: <String, RawRule>{}),
      scopeName: map['scopeName'] as ScopeName,
      patterns: ((map['patterns'] as List<Object?>?) ?? const <Object?>[])
          .map((entry) => RawRule.fromMap(entry as Map<Object?, Object?>))
          .toList(growable: false),
      injections: convertRuleMap(map['injections']),
      injectionSelector: map['injectionSelector'] as String?,
      fileTypes: (map['fileTypes'] as List<Object?>?)
          ?.map((entry) => entry as String)
          .toList(growable: false),
      name: map['name'] as String?,
      firstLineMatch: map['firstLineMatch'] as String?,
      location: map[r'$vscodeTextmateLocation'] is Map
          ? Location.fromMap(
              map[r'$vscodeTextmateLocation'] as Map<Object?, Object?>,
            )
          : null,
    );
  }
}
