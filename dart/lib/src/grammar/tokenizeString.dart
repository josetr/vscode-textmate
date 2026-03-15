part of 'grammar.dart';

class TokenizeStringResult {
  const TokenizeStringResult({required this.stack, required this.stoppedEarly});

  final StateStackImpl stack;
  final bool stoppedEarly;
}

TokenizeStringResult _tokenizeString(
  Grammar grammar,
  OnigString lineText,
  bool isFirstLine,
  int linePos,
  StateStackImpl stack,
  LineTokens lineTokens,
  LineFonts lineFonts,
  bool shouldCheckWhileConditions,
  int timeLimit,
) {
  void produce(StateStackImpl stack, int endIndex) {
    lineTokens.produce(stack, endIndex);
    lineFonts.produce(stack, endIndex);
  }

  final lineLength = lineText.content.length;
  var stop = false;
  var anchorPosition = -1;

  if (shouldCheckWhileConditions) {
    final whileCheckResult = checkWhileConditions(
      grammar,
      lineText,
      isFirstLine,
      linePos,
      stack,
      lineTokens,
      lineFonts,
    );
    stack = whileCheckResult.stack;
    linePos = whileCheckResult.linePos;
    isFirstLine = whileCheckResult.isFirstLine;
    anchorPosition = whileCheckResult.anchorPosition;
  }

  final startTime = DateTime.now().millisecondsSinceEpoch;
  while (!stop) {
    if (timeLimit != 0) {
      final elapsedTime = DateTime.now().millisecondsSinceEpoch - startTime;
      if (elapsedTime > timeLimit) {
        return TokenizeStringResult(stack: stack, stoppedEarly: true);
      }
    }

    final result = matchRuleOrInjections(
      grammar,
      lineText,
      isFirstLine,
      linePos,
      stack,
      anchorPosition,
    );

    if (result == null) {
      produce(stack, lineLength);
      stop = true;
      continue;
    }

    final captureIndices = result.captureIndices;
    final matchedRuleId = result.matchedRuleId;
    final hasAdvanced = captureIndices.isNotEmpty
        ? captureIndices[0].end > linePos
        : false;

    if (matchedRuleId == endRuleId) {
      final poppedRule = stack.getRule(grammar) as BeginEndRule;
      produce(stack, captureIndices[0].start);
      stack = stack.withContentNameScopesList(stack.nameScopesList!);
      handleCaptures(
        grammar,
        lineText,
        isFirstLine,
        stack,
        lineTokens,
        lineFonts,
        poppedRule.endCaptures,
        captureIndices,
      );
      produce(stack, captureIndices[0].end);

      final popped = stack;
      stack = stack.parent!;
      anchorPosition = popped.getAnchorPos();

      if (!hasAdvanced && popped.getEnterPos() == linePos) {
        stack = popped;
        produce(stack, lineLength);
        stop = true;
      }
    } else {
      final rule = grammar.getRule(matchedRuleId);
      produce(stack, captureIndices[0].start);

      final beforePush = stack;
      final scopeName = rule.getName(lineText.content, captureIndices);
      final nameScopesList = stack.contentNameScopesList!.pushAttributed(
        scopeName,
        grammar,
      );
      stack = stack.push(
        matchedRuleId,
        linePos,
        anchorPosition,
        captureIndices[0].end == lineLength,
        null,
        nameScopesList,
        nameScopesList,
      );

      if (rule is BeginEndRule) {
        handleCaptures(
          grammar,
          lineText,
          isFirstLine,
          stack,
          lineTokens,
          lineFonts,
          rule.beginCaptures,
          captureIndices,
        );
        produce(stack, captureIndices[0].end);
        anchorPosition = captureIndices[0].end;
        final contentName = rule.getContentName(
          lineText.content,
          captureIndices,
        );
        final contentNameScopesList = nameScopesList.pushAttributed(
          contentName,
          grammar,
        );
        stack = stack.withContentNameScopesList(contentNameScopesList);

        if (rule.endHasBackReferences) {
          stack = stack.withEndRule(
            rule.getEndWithResolvedBackReferences(
              lineText.content,
              captureIndices,
            ),
          );
        }

        if (!hasAdvanced && beforePush.hasSameRuleAs(stack)) {
          stack = stack.pop()!;
          produce(stack, lineLength);
          stop = true;
        }
      } else if (rule is BeginWhileRule) {
        handleCaptures(
          grammar,
          lineText,
          isFirstLine,
          stack,
          lineTokens,
          lineFonts,
          rule.beginCaptures,
          captureIndices,
        );
        produce(stack, captureIndices[0].end);
        anchorPosition = captureIndices[0].end;
        final contentName = rule.getContentName(
          lineText.content,
          captureIndices,
        );
        final contentNameScopesList = nameScopesList.pushAttributed(
          contentName,
          grammar,
        );
        stack = stack.withContentNameScopesList(contentNameScopesList);

        if (rule.whileHasBackReferences) {
          stack = stack.withEndRule(
            rule.getWhileWithResolvedBackReferences(
              lineText.content,
              captureIndices,
            ),
          );
        }

        if (!hasAdvanced && beforePush.hasSameRuleAs(stack)) {
          stack = stack.pop()!;
          produce(stack, lineLength);
          stop = true;
        }
      } else {
        final matchingRule = rule as MatchRule;
        handleCaptures(
          grammar,
          lineText,
          isFirstLine,
          stack,
          lineTokens,
          lineFonts,
          matchingRule.captures,
          captureIndices,
        );
        produce(stack, captureIndices[0].end);
        stack = stack.pop()!;

        if (!hasAdvanced) {
          stack = stack.safePop();
          produce(stack, lineLength);
          stop = true;
        }
      }
    }

    if (captureIndices[0].end > linePos) {
      linePos = captureIndices[0].end;
      isFirstLine = false;
    }
  }

  return TokenizeStringResult(stack: stack, stoppedEarly: false);
}

class WhileCheckResult {
  const WhileCheckResult({
    required this.stack,
    required this.linePos,
    required this.anchorPosition,
    required this.isFirstLine,
  });

  final StateStackImpl stack;
  final int linePos;
  final int anchorPosition;
  final bool isFirstLine;
}

WhileCheckResult checkWhileConditions(
  Grammar grammar,
  OnigString lineText,
  bool isFirstLine,
  int linePos,
  StateStackImpl stack,
  LineTokens lineTokens,
  LineFonts lineFonts,
) {
  void produce(StateStackImpl stack, int endIndex) {
    lineTokens.produce(stack, endIndex);
    lineFonts.produce(stack, endIndex);
  }

  var anchorPosition = stack.beginRuleCapturedEOL ? 0 : -1;
  final whileRules = <WhileStack>[];
  for (StateStackImpl? node = stack; node != null; node = node.pop()) {
    final nodeRule = node.getRule(grammar);
    if (nodeRule is BeginWhileRule) {
      whileRules.add(WhileStack(stack: node, rule: nodeRule));
    }
  }

  while (whileRules.isNotEmpty) {
    final whileRule = whileRules.removeLast();
    final prepared = prepareRuleWhileSearch(
      whileRule.rule,
      grammar,
      whileRule.stack.endRule,
      isFirstLine,
      linePos == anchorPosition,
    );
    final result = prepared.ruleScanner.findNextMatchSync(
      lineText,
      linePos,
      prepared.findOptions,
    );

    if (result != null) {
      if (result.ruleId != whileRuleId) {
        stack = whileRule.stack.pop()!;
        break;
      }
      if (result.captureIndices.isNotEmpty) {
        produce(whileRule.stack, result.captureIndices[0].start);
        handleCaptures(
          grammar,
          lineText,
          isFirstLine,
          whileRule.stack,
          lineTokens,
          lineFonts,
          whileRule.rule.whileCaptures,
          result.captureIndices,
        );
        produce(whileRule.stack, result.captureIndices[0].end);
        anchorPosition = result.captureIndices[0].end;
        if (result.captureIndices[0].end > linePos) {
          linePos = result.captureIndices[0].end;
          isFirstLine = false;
        }
      }
    } else {
      stack = whileRule.stack.pop()!;
      break;
    }
  }

  return WhileCheckResult(
    stack: stack,
    linePos: linePos,
    anchorPosition: anchorPosition,
    isFirstLine: isFirstLine,
  );
}

class WhileStack {
  const WhileStack({required this.stack, required this.rule});

  final StateStackImpl stack;
  final BeginWhileRule rule;
}

class MatchResult {
  const MatchResult({
    required this.captureIndices,
    required this.matchedRuleId,
  });

  final List<OnigCaptureIndex> captureIndices;
  final int matchedRuleId;
}

class MatchInjectionsResult extends MatchResult {
  const MatchInjectionsResult({
    required this.priorityMatch,
    required super.captureIndices,
    required super.matchedRuleId,
  });

  final bool priorityMatch;
}

MatchResult? matchRuleOrInjections(
  Grammar grammar,
  OnigString lineText,
  bool isFirstLine,
  int linePos,
  StateStackImpl stack,
  int anchorPosition,
) {
  final matchResult = matchRule(
    grammar,
    lineText,
    isFirstLine,
    linePos,
    stack,
    anchorPosition,
  );

  final injections = grammar.getInjections();
  if (injections.isEmpty) {
    return matchResult;
  }

  final injectionResult = matchInjections(
    injections,
    grammar,
    lineText,
    isFirstLine,
    linePos,
    stack,
    anchorPosition,
  );
  if (injectionResult == null) {
    return matchResult;
  }
  if (matchResult == null) {
    return injectionResult;
  }

  final matchScore = matchResult.captureIndices[0].start;
  final injectionScore = injectionResult.captureIndices[0].start;
  if (injectionScore < matchScore ||
      (injectionResult.priorityMatch && injectionScore == matchScore)) {
    return injectionResult;
  }
  return matchResult;
}

MatchResult? matchRule(
  Grammar grammar,
  OnigString lineText,
  bool isFirstLine,
  int linePos,
  StateStackImpl stack,
  int anchorPosition,
) {
  final rule = stack.getRule(grammar);
  final prepared = prepareRuleSearch(
    rule,
    grammar,
    stack.endRule,
    isFirstLine,
    linePos == anchorPosition,
  );
  final result = prepared.ruleScanner.findNextMatchSync(
    lineText,
    linePos,
    prepared.findOptions,
  );
  if (result == null) {
    return null;
  }
  return MatchResult(
    captureIndices: result.captureIndices,
    matchedRuleId: result.ruleId,
  );
}

MatchInjectionsResult? matchInjections(
  List<Injection> injections,
  Grammar grammar,
  OnigString lineText,
  bool isFirstLine,
  int linePos,
  StateStackImpl stack,
  int anchorPosition,
) {
  var bestMatchRating = 1 << 30;
  List<OnigCaptureIndex>? bestMatchCaptureIndices;
  int? bestMatchRuleId;
  var bestMatchResultPriority = 0;
  final scopes = stack.contentNameScopesList!.getScopeNames();

  for (final injection in injections) {
    if (!injection.matcher(scopes)) {
      continue;
    }
    final rule = grammar.getRule(injection.ruleId);
    final prepared = prepareRuleSearch(
      rule,
      grammar,
      null,
      isFirstLine,
      linePos == anchorPosition,
    );
    final matchResult = prepared.ruleScanner.findNextMatchSync(
      lineText,
      linePos,
      prepared.findOptions,
    );
    if (matchResult == null) {
      continue;
    }

    final matchRating = matchResult.captureIndices[0].start;
    if (matchRating >= bestMatchRating) {
      continue;
    }

    bestMatchRating = matchRating;
    bestMatchCaptureIndices = matchResult.captureIndices;
    bestMatchRuleId = matchResult.ruleId;
    bestMatchResultPriority = injection.priority;

    if (bestMatchRating == linePos) {
      break;
    }
  }

  if (bestMatchCaptureIndices == null || bestMatchRuleId == null) {
    return null;
  }
  return MatchInjectionsResult(
    priorityMatch: bestMatchResultPriority == -1,
    captureIndices: bestMatchCaptureIndices,
    matchedRuleId: bestMatchRuleId,
  );
}

class PreparedRuleSearch<TRuleId> {
  const PreparedRuleSearch({
    required this.ruleScanner,
    required this.findOptions,
  });

  final CompiledRule<TRuleId> ruleScanner;
  final int findOptions;
}

PreparedRuleSearch<int> prepareRuleSearch(
  Rule rule,
  Grammar grammar,
  String? endRegexSource,
  bool allowA,
  bool allowG,
) {
  if (useOnigurumaFindOptions) {
    final ruleScanner = rule.compile(grammar, endRegexSource);
    final findOptions = getFindOptions(allowA, allowG);
    return PreparedRuleSearch(
      ruleScanner: ruleScanner,
      findOptions: findOptions,
    );
  }
  final ruleScanner = rule.compileAG(grammar, endRegexSource, allowA, allowG);
  return PreparedRuleSearch(
    ruleScanner: ruleScanner,
    findOptions: FindOption.none,
  );
}

PreparedRuleSearch<int> prepareRuleWhileSearch(
  BeginWhileRule rule,
  Grammar grammar,
  String? endRegexSource,
  bool allowA,
  bool allowG,
) {
  if (useOnigurumaFindOptions) {
    final ruleScanner = rule.compileWhile(grammar, endRegexSource);
    final findOptions = getFindOptions(allowA, allowG);
    return PreparedRuleSearch(
      ruleScanner: ruleScanner,
      findOptions: findOptions,
    );
  }
  final ruleScanner = rule.compileWhileAG(
    grammar,
    endRegexSource,
    allowA,
    allowG,
  );
  return PreparedRuleSearch(
    ruleScanner: ruleScanner,
    findOptions: FindOption.none,
  );
}

int getFindOptions(bool allowA, bool allowG) {
  var options = FindOption.none;
  if (!allowA) {
    options |= FindOption.notBeginString;
  }
  if (!allowG) {
    options |= FindOption.notBeginPosition;
  }
  return options;
}

void handleCaptures(
  Grammar grammar,
  OnigString lineText,
  bool isFirstLine,
  StateStackImpl stack,
  LineTokens lineTokens,
  LineFonts lineFonts,
  List<CaptureRule?> captures,
  List<OnigCaptureIndex> captureIndices,
) {
  void produceFromScopes(AttributedScopeStack? scopesList, int endIndex) {
    lineTokens.produceFromScopes(scopesList, endIndex);
    lineFonts.produceFromScopes(scopesList, endIndex);
  }

  void produce(StateStackImpl stack, int endIndex) {
    lineTokens.produce(stack, endIndex);
    lineFonts.produce(stack, endIndex);
  }

  if (captures.isEmpty) {
    return;
  }

  final lineTextContent = lineText.content;
  final length = captures.length < captureIndices.length
      ? captures.length
      : captureIndices.length;
  final localStack = <LocalStackElement>[];
  final maxEnd = captureIndices[0].end;

  for (var i = 0; i < length; i++) {
    final captureRule = captures[i];
    if (captureRule == null) {
      continue;
    }

    final captureIndex = captureIndices[i];
    if (captureIndex.length == 0) {
      continue;
    }
    if (captureIndex.start > maxEnd) {
      break;
    }

    while (localStack.isNotEmpty &&
        localStack.last.endPos <= captureIndex.start) {
      produceFromScopes(localStack.last.scopes, localStack.last.endPos);
      localStack.removeLast();
    }

    if (localStack.isNotEmpty) {
      produceFromScopes(localStack.last.scopes, captureIndex.start);
    } else {
      produce(stack, captureIndex.start);
    }

    if (captureRule.retokenizeCapturedWithRuleId != 0) {
      final scopeName = captureRule.getName(lineTextContent, captureIndices);
      final nameScopesList = stack.contentNameScopesList!.pushAttributed(
        scopeName,
        grammar,
      );
      final contentName = captureRule.getContentName(
        lineTextContent,
        captureIndices,
      );
      final contentNameScopesList = nameScopesList.pushAttributed(
        contentName,
        grammar,
      );
      final stackClone = stack.push(
        captureRule.retokenizeCapturedWithRuleId,
        captureIndex.start,
        -1,
        false,
        null,
        nameScopesList,
        contentNameScopesList,
      );
      final onigSubStr = grammar.createOnigString(
        lineTextContent.substring(0, captureIndex.end),
      );
      _tokenizeString(
        grammar,
        onigSubStr,
        isFirstLine && captureIndex.start == 0,
        captureIndex.start,
        stackClone,
        lineTokens,
        lineFonts,
        false,
        0,
      );
      disposeOnigString(onigSubStr);
      continue;
    }

    final captureRuleScopeName = captureRule.getName(
      lineTextContent,
      captureIndices,
    );
    if (captureRuleScopeName != null) {
      final base = localStack.isNotEmpty
          ? localStack.last.scopes
          : stack.contentNameScopesList!;
      final captureRuleScopesList = base.pushAttributed(
        captureRuleScopeName,
        grammar,
      );
      localStack.add(
        LocalStackElement(captureRuleScopesList, captureIndex.end),
      );
    }
  }

  while (localStack.isNotEmpty) {
    produceFromScopes(localStack.last.scopes, localStack.last.endPos);
    localStack.removeLast();
  }
}

class LocalStackElement {
  const LocalStackElement(this.scopes, this.endPos);

  final AttributedScopeStack scopes;
  final int endPos;
}
