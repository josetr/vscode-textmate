import 'utils.dart';

typedef ScopeName = String;
typedef ScopePath = String;
typedef ScopePattern = String;

class RawTheme {
  const RawTheme({this.name, required this.settings});

  final String? name;
  final List<RawThemeSetting> settings;
}

class RawThemeSetting {
  const RawThemeSetting({this.name, this.scope, required this.settings});

  final String? name;
  final Object? scope;
  final RawThemeSettingData settings;
}

class RawThemeSettingData {
  const RawThemeSettingData({
    this.fontStyle,
    this.foreground,
    this.background,
    this.fontFamily,
    this.fontSize,
    this.lineHeight,
  });

  final String? fontStyle;
  final String? foreground;
  final String? background;
  final String? fontFamily;
  final double? fontSize;
  final double? lineHeight;
}

class FontStyle {
  static const int notSet = -1;
  static const int none = 0;
  static const int italic = 1;
  static const int bold = 2;
  static const int underline = 4;
  static const int strikethrough = 8;
}

String fontStyleToString(int fontStyle) {
  if (fontStyle == FontStyle.notSet) {
    return 'not set';
  }

  final style = <String>[];
  if ((fontStyle & FontStyle.italic) != 0) {
    style.add('italic');
  }
  if ((fontStyle & FontStyle.bold) != 0) {
    style.add('bold');
  }
  if ((fontStyle & FontStyle.underline) != 0) {
    style.add('underline');
  }
  if ((fontStyle & FontStyle.strikethrough) != 0) {
    style.add('strikethrough');
  }
  if (style.isEmpty) {
    return 'none';
  }
  return style.join(' ');
}

class StyleAttributes {
  const StyleAttributes(
    this.fontStyle,
    this.foregroundId,
    this.backgroundId,
    this.fontFamily,
    this.fontSize,
    this.lineHeight,
  );

  final int fontStyle;
  final int foregroundId;
  final int backgroundId;
  final String fontFamily;
  final double fontSize;
  final double lineHeight;
}

class ScopeStack {
  const ScopeStack(this.parent, this.scopeName);

  final ScopeStack? parent;
  final ScopeName scopeName;

  static ScopeStack? push(ScopeStack? path, List<ScopeName> scopeNames) {
    var result = path;
    for (final name in scopeNames) {
      result = ScopeStack(result, name);
    }
    return result;
  }

  static ScopeStack? fromSegments(List<ScopeName> segments) {
    ScopeStack? result;
    for (final segment in segments) {
      result = ScopeStack(result, segment);
    }
    return result;
  }

  ScopeStack pushScope(ScopeName name) => ScopeStack(this, name);

  List<ScopeName> getSegments() {
    final result = <ScopeName>[];
    ScopeStack? item = this;
    while (item != null) {
      result.add(item.scopeName);
      item = item.parent;
    }
    return result.reversed.toList(growable: false);
  }

  bool extendsPath(ScopeStack other) {
    if (identical(this, other)) {
      return true;
    }
    if (parent == null) {
      return false;
    }
    return parent!.extendsPath(other);
  }

  List<String>? getExtensionIfDefined(ScopeStack? base) {
    final result = <String>[];
    ScopeStack? item = this;
    while (item != null && !identical(item, base)) {
      result.add(item.scopeName);
      item = item.parent;
    }
    if (!identical(item, base)) {
      return null;
    }
    return result.reversed.toList(growable: false);
  }

  @override
  String toString() => getSegments().join(' ');
}

class ParsedThemeRule {
  const ParsedThemeRule(
    this.scope,
    this.parentScopes,
    this.index,
    this.fontStyle,
    this.foreground,
    this.background,
    this.fontFamily,
    this.fontSize,
    this.lineHeight,
  );

  final ScopeName scope;
  final List<ScopeName>? parentScopes;
  final int index;
  final int fontStyle;
  final String? foreground;
  final String? background;
  final String fontFamily;
  final double fontSize;
  final double lineHeight;
}

class Theme {
  Theme(this._colorMap, this._defaults, ThemeTrieElement root)
    : _cachedMatchRoot = CachedFn<ScopeName, List<ThemeTrieElementRule>>((
        scopeName,
      ) {
        return root.match(scopeName);
      });

  final ColorMap _colorMap;
  final StyleAttributes _defaults;
  final CachedFn<ScopeName, List<ThemeTrieElementRule>> _cachedMatchRoot;

  static Theme createFromRawTheme(RawTheme? source, [List<String>? colorMap]) {
    return createFromParsedTheme(parseTheme(source), colorMap);
  }

  static Theme createFromParsedTheme(
    List<ParsedThemeRule> source, [
    List<String>? colorMap,
  ]) {
    return _resolveParsedThemeRules(source, colorMap);
  }

  List<String> getColorMap() => _colorMap.getColorMap();

  StyleAttributes getDefaults() => _defaults;

  StyleAttributes? match(ScopeStack? scopePath) {
    if (scopePath == null) {
      return _defaults;
    }
    final matchingTrieElements = _cachedMatchRoot.get(scopePath.scopeName);
    ThemeTrieElementRule? effectiveRule;
    for (final rule in matchingTrieElements) {
      if (_scopePathMatchesParentScopes(scopePath.parent, rule.parentScopes)) {
        effectiveRule = rule;
        break;
      }
    }
    if (effectiveRule == null) {
      return null;
    }
    return StyleAttributes(
      effectiveRule.fontStyle,
      effectiveRule.foreground,
      effectiveRule.background,
      effectiveRule.fontFamily,
      effectiveRule.fontSize,
      effectiveRule.lineHeight,
    );
  }
}

List<ParsedThemeRule> parseTheme(RawTheme? source) {
  if (source == null) {
    return <ParsedThemeRule>[];
  }

  final result = <ParsedThemeRule>[];
  for (var i = 0; i < source.settings.length; i++) {
    final entry = source.settings[i];
    final settings = entry.settings;

    List<String> scopes;
    if (entry.scope is String) {
      var scope = entry.scope! as String;
      scope = scope.replaceFirst(RegExp(r'^[,]+'), '');
      scope = scope.replaceFirst(RegExp(r'[,]+$'), '');
      scopes = scope.split(',');
    } else if (entry.scope is List) {
      scopes = (entry.scope! as List<Object?>).cast<String>();
    } else {
      scopes = <String>[''];
    }

    var fontStyle = FontStyle.notSet;
    if (settings.fontStyle != null) {
      fontStyle = FontStyle.none;
      for (final segment in settings.fontStyle!.split(' ')) {
        switch (segment) {
          case 'italic':
            fontStyle |= FontStyle.italic;
            break;
          case 'bold':
            fontStyle |= FontStyle.bold;
            break;
          case 'underline':
            fontStyle |= FontStyle.underline;
            break;
          case 'strikethrough':
            fontStyle |= FontStyle.strikethrough;
            break;
        }
      }
    }

    final foreground =
        settings.foreground != null && isValidHexColor(settings.foreground!)
        ? settings.foreground
        : null;
    final background =
        settings.background != null && isValidHexColor(settings.background!)
        ? settings.background
        : null;
    final fontFamily = settings.fontFamily ?? '';
    final fontSize = settings.fontSize ?? 0;
    final lineHeight = settings.lineHeight ?? 0;

    for (final rawScope in scopes) {
      final trimmedScope = rawScope.trim();
      final segments = trimmedScope.split(' ');
      final scope = segments.last;
      List<String>? parentScopes;
      if (segments.length > 1) {
        parentScopes = segments
            .sublist(0, segments.length - 1)
            .reversed
            .toList();
      }

      result.add(
        ParsedThemeRule(
          scope,
          parentScopes,
          i,
          fontStyle,
          foreground,
          background,
          fontFamily,
          fontSize,
          lineHeight,
        ),
      );
    }
  }

  return result;
}

class ColorMap {
  ColorMap([List<String>? colorMap])
    : _isFrozen = colorMap != null,
      _lastColorId = 0,
      _id2color = <String>[''],
      _color2id = <String, int>{} {
    if (colorMap != null) {
      for (var i = 0; i < colorMap.length; i++) {
        _color2id[colorMap[i]] = i;
        while (_id2color.length <= i) {
          _id2color.add('');
        }
        _id2color[i] = colorMap[i];
      }
    }
  }

  final bool _isFrozen;
  int _lastColorId;
  final List<String> _id2color;
  final Map<String, int> _color2id;

  int getId(String? color) {
    if (color == null) {
      return 0;
    }
    final normalized = color.toUpperCase();
    final existing = _color2id[normalized];
    if (existing != null && existing != 0) {
      return existing;
    }
    if (_isFrozen) {
      throw StateError('Missing color in color map - $normalized');
    }
    final value = ++_lastColorId;
    _color2id[normalized] = value;
    while (_id2color.length <= value) {
      _id2color.add('');
    }
    _id2color[value] = normalized;
    return value;
  }

  List<String> getColorMap() => List<String>.from(_id2color);
}

const List<ScopeName> _emptyParentScopes = <ScopeName>[];

class ThemeTrieElementRule {
  ThemeTrieElementRule(
    this.scopeDepth,
    List<ScopeName>? parentScopes,
    this.fontStyle,
    this.foreground,
    this.background,
    this.fontFamily,
    this.fontSize,
    this.lineHeight,
  ) : parentScopes = parentScopes ?? _emptyParentScopes;

  int scopeDepth;
  final List<ScopeName> parentScopes;
  int fontStyle;
  int foreground;
  int background;
  String fontFamily;
  double fontSize;
  double lineHeight;

  ThemeTrieElementRule clone() => ThemeTrieElementRule(
    scopeDepth,
    parentScopes,
    fontStyle,
    foreground,
    background,
    fontFamily,
    fontSize,
    lineHeight,
  );

  static List<ThemeTrieElementRule> cloneArr(List<ThemeTrieElementRule> arr) {
    return arr.map((entry) => entry.clone()).toList(growable: false);
  }

  void acceptOverwrite(
    int scopeDepth,
    int fontStyle,
    int foreground,
    int background,
    String fontFamily,
    double fontSize,
    double lineHeight,
  ) {
    if (this.scopeDepth <= scopeDepth) {
      this.scopeDepth = scopeDepth;
    }
    if (fontStyle != FontStyle.notSet) {
      this.fontStyle = fontStyle;
    }
    if (foreground != 0) {
      this.foreground = foreground;
    }
    if (background != 0) {
      this.background = background;
    }
    if (fontFamily.isNotEmpty) {
      this.fontFamily = fontFamily;
    }
    if (fontSize != 0) {
      this.fontSize = fontSize;
    }
    if (lineHeight != 0) {
      this.lineHeight = lineHeight;
    }
  }
}

class ThemeTrieElement {
  ThemeTrieElement(
    this._mainRule, [
    List<ThemeTrieElementRule> rulesWithParentScopes =
        const <ThemeTrieElementRule>[],
    Map<String, ThemeTrieElement> children = const <String, ThemeTrieElement>{},
  ]) : _rulesWithParentScopes = List<ThemeTrieElementRule>.from(
         rulesWithParentScopes,
       ),
       _children = Map<String, ThemeTrieElement>.from(children);

  final ThemeTrieElementRule _mainRule;
  final List<ThemeTrieElementRule> _rulesWithParentScopes;
  final Map<String, ThemeTrieElement> _children;

  static int _cmpBySpecificity(ThemeTrieElementRule a, ThemeTrieElementRule b) {
    if (a.scopeDepth != b.scopeDepth) {
      return b.scopeDepth - a.scopeDepth;
    }

    var aParentIndex = 0;
    var bParentIndex = 0;
    while (true) {
      if (aParentIndex < a.parentScopes.length &&
          a.parentScopes[aParentIndex] == '>') {
        aParentIndex++;
      }
      if (bParentIndex < b.parentScopes.length &&
          b.parentScopes[bParentIndex] == '>') {
        bParentIndex++;
      }

      if (aParentIndex >= a.parentScopes.length ||
          bParentIndex >= b.parentScopes.length) {
        break;
      }

      final diff =
          b.parentScopes[bParentIndex].length -
          a.parentScopes[aParentIndex].length;
      if (diff != 0) {
        return diff;
      }

      aParentIndex++;
      bParentIndex++;
    }

    return b.parentScopes.length - a.parentScopes.length;
  }

  List<ThemeTrieElementRule> match(ScopeName scope) {
    if (scope.isNotEmpty) {
      final dotIndex = scope.indexOf('.');
      final head = dotIndex == -1 ? scope : scope.substring(0, dotIndex);
      final tail = dotIndex == -1 ? '' : scope.substring(dotIndex + 1);
      final child = _children[head];
      if (child != null) {
        return child.match(tail);
      }
    }

    final rules = <ThemeTrieElementRule>[..._rulesWithParentScopes, _mainRule];
    rules.sort(_cmpBySpecificity);
    return rules;
  }

  void insert(
    int scopeDepth,
    ScopeName scope,
    List<ScopeName>? parentScopes,
    int fontStyle,
    int foreground,
    int background,
    String fontFamily,
    double fontSize,
    double lineHeight,
  ) {
    if (scope.isEmpty) {
      _doInsertHere(
        scopeDepth,
        parentScopes,
        fontStyle,
        foreground,
        background,
        fontFamily,
        fontSize,
        lineHeight,
      );
      return;
    }

    final dotIndex = scope.indexOf('.');
    final head = dotIndex == -1 ? scope : scope.substring(0, dotIndex);
    final tail = dotIndex == -1 ? '' : scope.substring(dotIndex + 1);
    final child = _children.putIfAbsent(
      head,
      () => ThemeTrieElement(
        _mainRule.clone(),
        ThemeTrieElementRule.cloneArr(_rulesWithParentScopes),
      ),
    );
    child.insert(
      scopeDepth + 1,
      tail,
      parentScopes,
      fontStyle,
      foreground,
      background,
      fontFamily,
      fontSize,
      lineHeight,
    );
  }

  void _doInsertHere(
    int scopeDepth,
    List<ScopeName>? parentScopes,
    int fontStyle,
    int foreground,
    int background,
    String fontFamily,
    double fontSize,
    double lineHeight,
  ) {
    if (parentScopes == null) {
      _mainRule.acceptOverwrite(
        scopeDepth,
        fontStyle,
        foreground,
        background,
        fontFamily,
        fontSize,
        lineHeight,
      );
      return;
    }

    for (final rule in _rulesWithParentScopes) {
      if (strArrCmp(rule.parentScopes, parentScopes) == 0) {
        rule.acceptOverwrite(
          scopeDepth,
          fontStyle,
          foreground,
          background,
          fontFamily,
          fontSize,
          lineHeight,
        );
        return;
      }
    }

    if (fontStyle == FontStyle.notSet) {
      fontStyle = _mainRule.fontStyle;
    }
    if (foreground == 0) {
      foreground = _mainRule.foreground;
    }
    if (background == 0) {
      background = _mainRule.background;
    }
    if (fontFamily.isEmpty) {
      fontFamily = _mainRule.fontFamily;
    }
    if (fontSize == 0) {
      fontSize = _mainRule.fontSize;
    }
    if (lineHeight == 0) {
      lineHeight = _mainRule.lineHeight;
    }

    _rulesWithParentScopes.add(
      ThemeTrieElementRule(
        scopeDepth,
        parentScopes,
        fontStyle,
        foreground,
        background,
        fontFamily,
        fontSize,
        lineHeight,
      ),
    );
  }
}

bool _scopePathMatchesParentScopes(
  ScopeStack? scopePath,
  List<ScopeName> parentScopes,
) {
  if (parentScopes.isEmpty) {
    return true;
  }

  for (var index = 0; index < parentScopes.length; index++) {
    var scopePattern = parentScopes[index];
    var scopeMustMatch = false;

    if (scopePattern == '>') {
      if (index == parentScopes.length - 1) {
        return false;
      }
      scopePattern = parentScopes[++index];
      scopeMustMatch = true;
    }

    while (scopePath != null) {
      if (_matchesScope(scopePath.scopeName, scopePattern)) {
        break;
      }
      if (scopeMustMatch) {
        return false;
      }
      scopePath = scopePath.parent;
    }

    if (scopePath == null) {
      return false;
    }
    scopePath = scopePath.parent;
  }

  return true;
}

bool _matchesScope(ScopeName scopeName, ScopeName scopePattern) {
  return scopePattern == scopeName ||
      (scopeName.startsWith(scopePattern) &&
          scopeName.length > scopePattern.length &&
          scopeName[scopePattern.length] == '.');
}

Theme _resolveParsedThemeRules(
  List<ParsedThemeRule> parsedThemeRules,
  List<String>? inputColorMap,
) {
  final sortedRules = List<ParsedThemeRule>.from(parsedThemeRules);
  sortedRules.sort((a, b) {
    var result = strcmp(a.scope, b.scope);
    if (result != 0) {
      return result;
    }
    result = strArrCmp(a.parentScopes, b.parentScopes);
    if (result != 0) {
      return result;
    }
    return a.index - b.index;
  });

  var defaultFontStyle = FontStyle.none;
  var defaultForeground = '#000000';
  var defaultBackground = '#ffffff';
  var defaultFontFamily = '';
  var defaultFontSize = 0.0;
  var defaultLineHeight = 0.0;

  while (sortedRules.isNotEmpty && sortedRules.first.scope.isEmpty) {
    final defaults = sortedRules.removeAt(0);
    if (defaults.fontStyle != FontStyle.notSet) {
      defaultFontStyle = defaults.fontStyle;
    }
    if (defaults.foreground != null) {
      defaultForeground = defaults.foreground!;
    }
    if (defaults.background != null) {
      defaultBackground = defaults.background!;
    }
    if (defaults.fontFamily.isNotEmpty) {
      defaultFontFamily = defaults.fontFamily;
    }
    if (defaults.fontSize != 0) {
      defaultFontSize = defaults.fontSize;
    }
    if (defaults.lineHeight != 0) {
      defaultLineHeight = defaults.lineHeight;
    }
  }

  final colorMap = ColorMap(inputColorMap);
  final defaults = StyleAttributes(
    defaultFontStyle,
    colorMap.getId(defaultForeground),
    colorMap.getId(defaultBackground),
    defaultFontFamily,
    defaultFontSize,
    defaultLineHeight,
  );

  final root = ThemeTrieElement(
    ThemeTrieElementRule(
      0,
      null,
      FontStyle.notSet,
      0,
      0,
      defaultFontFamily,
      defaultFontSize,
      defaultLineHeight,
    ),
  );

  for (final rule in sortedRules) {
    root.insert(
      0,
      rule.scope,
      rule.parentScopes,
      rule.fontStyle,
      colorMap.getId(rule.foreground),
      colorMap.getId(rule.background),
      rule.fontFamily,
      rule.fontSize,
      rule.lineHeight,
    );
  }

  return Theme(colorMap, defaults, root);
}
