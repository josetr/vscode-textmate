typedef Matcher<T> = bool Function(T matcherInput);

class MatcherWithPriority<T> {
  const MatcherWithPriority({required this.matcher, required this.priority});

  final Matcher<T> matcher;
  final int priority;
}

List<MatcherWithPriority<T>> createMatchers<T>(
  String selector,
  bool Function(List<String> names, T matcherInput) matchesName,
) {
  final results = <MatcherWithPriority<T>>[];
  final tokenizer = _Tokenizer(selector);
  String? token = tokenizer.next();

  late Matcher<T>? Function() parseOperand;
  late Matcher<T> Function() parseConjunction;
  late Matcher<T> Function() parseInnerExpression;

  parseOperand = () {
    if (token == '-') {
      token = tokenizer.next();
      final expressionToNegate = parseOperand();
      return (matcherInput) =>
          expressionToNegate != null && !expressionToNegate(matcherInput);
    }
    if (token == '(') {
      token = tokenizer.next();
      final expressionInParents = parseInnerExpression();
      if (token == ')') {
        token = tokenizer.next();
      }
      return expressionInParents;
    }
    if (_isIdentifier(token)) {
      final identifiers = <String>[];
      do {
        identifiers.add(token!);
        token = tokenizer.next();
      } while (_isIdentifier(token));
      return (matcherInput) => matchesName(identifiers, matcherInput);
    }
    return null;
  };

  parseConjunction = () {
    final matchers = <Matcher<T>>[];
    var matcher = parseOperand();
    while (matcher != null) {
      matchers.add(matcher);
      matcher = parseOperand();
    }
    return (matcherInput) => matchers.every((matcher) => matcher(matcherInput));
  };

  parseInnerExpression = () {
    final matchers = <Matcher<T>>[];
    var matcher = parseConjunction();
    while (true) {
      matchers.add(matcher);
      if (token == '|' || token == ',') {
        do {
          token = tokenizer.next();
        } while (token == '|' || token == ',');
      } else {
        break;
      }
      matcher = parseConjunction();
    }
    return (matcherInput) => matchers.any((matcher) => matcher(matcherInput));
  };

  while (token != null) {
    var priority = 0;
    final currentToken = token!;
    if (currentToken.length == 2 && currentToken[1] == ':') {
      switch (currentToken[0]) {
        case 'R':
          priority = 1;
          break;
        case 'L':
          priority = -1;
          break;
      }
      token = tokenizer.next();
    }

    results.add(
      MatcherWithPriority<T>(matcher: parseConjunction(), priority: priority),
    );

    if (token != ',') {
      break;
    }
    token = tokenizer.next();
  }

  return results;
}

bool _isIdentifier(String? token) =>
    token != null && RegExp(r'^[\w\.:]+$').hasMatch(token);

class _Tokenizer {
  _Tokenizer(String input)
    : _matches = RegExp(
        r'([LR]:|[\w\.:][\w\.:\-]*|[\,\|\-\(\)])',
      ).allMatches(input).toList();

  final List<RegExpMatch> _matches;
  int _index = 0;

  String? next() {
    if (_index >= _matches.length) {
      return null;
    }
    return _matches[_index++].group(0);
  }
}
