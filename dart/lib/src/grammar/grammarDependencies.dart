import '../rawGrammar.dart';
import '../theme.dart';
import '../utils.dart';

abstract class GrammarRepository {
  RawGrammar? lookup(ScopeName scopeName);

  List<ScopeName> injections(ScopeName scopeName);
}

abstract class AbsoluteRuleReference {
  String toKey();
}

class TopLevelRuleReference implements AbsoluteRuleReference {
  TopLevelRuleReference(this.scopeName);

  final ScopeName scopeName;

  @override
  String toKey() => scopeName;
}

class TopLevelRepositoryRuleReference implements AbsoluteRuleReference {
  TopLevelRepositoryRuleReference(this.scopeName, this.ruleName);

  final ScopeName scopeName;
  final String ruleName;

  @override
  String toKey() => '$scopeName#$ruleName';
}

class ExternalReferenceCollector {
  final List<AbsoluteRuleReference> _references = <AbsoluteRuleReference>[];
  final Set<String> _seenReferenceKeys = <String>{};
  final Set<RawRule> visitedRule = <RawRule>{};

  List<AbsoluteRuleReference> get references => _references;

  void add(AbsoluteRuleReference reference) {
    final key = reference.toKey();
    if (_seenReferenceKeys.contains(key)) {
      return;
    }
    _seenReferenceKeys.add(key);
    _references.add(reference);
  }
}

class ScopeDependencyProcessor {
  ScopeDependencyProcessor(this.repo, this.initialScopeName) {
    seenFullScopeRequests.add(initialScopeName);
    q = <AbsoluteRuleReference>[TopLevelRuleReference(initialScopeName)];
  }

  final GrammarRepository repo;
  final ScopeName initialScopeName;
  final Set<ScopeName> seenFullScopeRequests = <ScopeName>{};
  final Set<String> seenPartialScopeRequests = <String>{};
  late List<AbsoluteRuleReference> q;

  void processQueue() {
    final currentQueue = q;
    q = <AbsoluteRuleReference>[];

    final deps = ExternalReferenceCollector();
    for (final dep in currentQueue) {
      _collectReferencesOfReference(dep, initialScopeName, repo, deps);
    }

    for (final dep in deps.references) {
      if (dep is TopLevelRuleReference) {
        if (seenFullScopeRequests.contains(dep.scopeName)) {
          continue;
        }
        seenFullScopeRequests.add(dep.scopeName);
        q.add(dep);
      } else if (dep is TopLevelRepositoryRuleReference) {
        if (seenFullScopeRequests.contains(dep.scopeName) ||
            seenPartialScopeRequests.contains(dep.toKey())) {
          continue;
        }
        seenPartialScopeRequests.add(dep.toKey());
        q.add(dep);
      }
    }
  }
}

void _collectReferencesOfReference(
  AbsoluteRuleReference reference,
  ScopeName baseGrammarScopeName,
  GrammarRepository repo,
  ExternalReferenceCollector result,
) {
  final scopeName = reference is TopLevelRuleReference
      ? reference.scopeName
      : (reference as TopLevelRepositoryRuleReference).scopeName;

  final selfGrammar = repo.lookup(scopeName);
  if (selfGrammar == null) {
    if (scopeName == baseGrammarScopeName) {
      throw StateError('No grammar provided for <$baseGrammarScopeName>');
    }
    return;
  }

  final baseGrammar = repo.lookup(baseGrammarScopeName)!;

  if (reference is TopLevelRuleReference) {
    _collectExternalReferencesInTopLevelRule(
      _Context(baseGrammar, selfGrammar),
      result,
    );
  } else {
    final repositoryReference = reference as TopLevelRepositoryRuleReference;
    _collectExternalReferencesInTopLevelRepositoryRule(
      repositoryReference.ruleName,
      _ContextWithRepository(
        baseGrammar,
        selfGrammar,
        selfGrammar.repository.values,
      ),
      result,
    );
  }

  for (final injection in repo.injections(scopeName)) {
    result.add(TopLevelRuleReference(injection));
  }
}

class _Context {
  const _Context(this.baseGrammar, this.selfGrammar);

  final RawGrammar baseGrammar;
  final RawGrammar selfGrammar;
}

class _ContextWithRepository extends _Context {
  const _ContextWithRepository(
    super.baseGrammar,
    super.selfGrammar,
    this.repository,
  );

  final Map<String, RawRule>? repository;
}

void _collectExternalReferencesInTopLevelRepositoryRule(
  String ruleName,
  _ContextWithRepository context,
  ExternalReferenceCollector result,
) {
  final rule = context.repository?[ruleName];
  if (rule != null) {
    _collectExternalReferencesInRules(<RawRule>[rule], context, result);
  }
}

void _collectExternalReferencesInTopLevelRule(
  _Context context,
  ExternalReferenceCollector result,
) {
  _collectExternalReferencesInRules(
    context.selfGrammar.patterns,
    _ContextWithRepository(
      context.baseGrammar,
      context.selfGrammar,
      context.selfGrammar.repository.values,
    ),
    result,
  );
  if (context.selfGrammar.injections != null) {
    _collectExternalReferencesInRules(
      context.selfGrammar.injections!.values.toList(growable: false),
      _ContextWithRepository(
        context.baseGrammar,
        context.selfGrammar,
        context.selfGrammar.repository.values,
      ),
      result,
    );
  }
}

void _collectExternalReferencesInRules(
  List<RawRule> rules,
  _ContextWithRepository context,
  ExternalReferenceCollector result,
) {
  for (final rule in rules) {
    if (result.visitedRule.contains(rule)) {
      continue;
    }
    result.visitedRule.add(rule);

    final patternRepository = rule.repository == null
        ? context.repository
        : mergeObjects(<String, Object?>{}, <Map<String, Object?>>[
            (context.repository ?? <String, RawRule>{}).cast<String, Object?>(),
            rule.repository!.values.cast<String, Object?>(),
          ]).cast<String, RawRule>();

    if (rule.patterns != null) {
      _collectExternalReferencesInRules(
        rule.patterns!,
        _ContextWithRepository(
          context.baseGrammar,
          context.selfGrammar,
          patternRepository,
        ),
        result,
      );
    }

    final include = rule.include;
    if (include == null) {
      continue;
    }

    final reference = parseInclude(include);
    switch (reference) {
      case BaseReference():
        _collectExternalReferencesInTopLevelRule(
          _Context(context.baseGrammar, context.baseGrammar),
          result,
        );
      case SelfReference():
        _collectExternalReferencesInTopLevelRule(context, result);
      case RelativeReference():
        _collectExternalReferencesInTopLevelRepositoryRule(
          reference.ruleName,
          _ContextWithRepository(
            context.baseGrammar,
            context.selfGrammar,
            patternRepository,
          ),
          result,
        );
      case TopLevelReference():
        final selfGrammar = reference.scopeName == context.selfGrammar.scopeName
            ? context.selfGrammar
            : reference.scopeName == context.baseGrammar.scopeName
            ? context.baseGrammar
            : null;
        if (selfGrammar != null) {
          _collectExternalReferencesInTopLevelRule(
            _ContextWithRepository(
              context.baseGrammar,
              selfGrammar,
              patternRepository,
            ),
            result,
          );
        } else {
          result.add(TopLevelRuleReference(reference.scopeName));
        }
      case TopLevelRepositoryReference():
        final selfGrammar = reference.scopeName == context.selfGrammar.scopeName
            ? context.selfGrammar
            : reference.scopeName == context.baseGrammar.scopeName
            ? context.baseGrammar
            : null;
        if (selfGrammar != null) {
          _collectExternalReferencesInTopLevelRepositoryRule(
            reference.ruleName,
            _ContextWithRepository(
              context.baseGrammar,
              selfGrammar,
              patternRepository,
            ),
            result,
          );
        } else {
          result.add(
            TopLevelRepositoryRuleReference(
              reference.scopeName,
              reference.ruleName,
            ),
          );
        }
    }
  }
}

sealed class IncludeReference {}

class BaseReference extends IncludeReference {}

class SelfReference extends IncludeReference {}

class RelativeReference extends IncludeReference {
  RelativeReference(this.ruleName);

  final String ruleName;
}

class TopLevelReference extends IncludeReference {
  TopLevelReference(this.scopeName);

  final ScopeName scopeName;
}

class TopLevelRepositoryReference extends IncludeReference {
  TopLevelRepositoryReference(this.scopeName, this.ruleName);

  final ScopeName scopeName;
  final String ruleName;
}

IncludeReference parseInclude(String include) {
  if (include == r'$base') {
    return BaseReference();
  }
  if (include == r'$self') {
    return SelfReference();
  }
  final indexOfSharp = include.indexOf('#');
  if (indexOfSharp == -1) {
    return TopLevelReference(include);
  }
  if (indexOfSharp == 0) {
    return RelativeReference(include.substring(1));
  }
  return TopLevelRepositoryReference(
    include.substring(0, indexOfSharp),
    include.substring(indexOfSharp + 1),
  );
}
