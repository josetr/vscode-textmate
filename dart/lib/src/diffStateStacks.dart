import 'grammar/grammar.dart';

class StackDiff {
  const StackDiff({required this.pops, required this.newFrames});

  final int pops;
  final List<StateStackFrame> newFrames;
}

StackDiff diffStateStacksRefEq(StateStack first, StateStack second) {
  var pops = 0;
  final newFrames = <StateStackFrame>[];

  var currentFirst = first as StateStackImpl?;
  var currentSecond = second as StateStackImpl?;

  while (!identical(currentFirst, currentSecond)) {
    if (currentFirst != null &&
        (currentSecond == null || currentFirst.depth >= currentSecond.depth)) {
      pops++;
      currentFirst = currentFirst.parent;
    } else {
      newFrames.add(currentSecond!.toStateStackFrame());
      currentSecond = currentSecond.parent;
    }
  }

  return StackDiff(
    pops: pops,
    newFrames: newFrames.reversed.toList(growable: false),
  );
}

StateStackImpl? applyStateStackDiff(StateStack? stack, StackDiff diff) {
  var currentStack = stack as StateStackImpl?;
  for (var i = 0; i < diff.pops; i++) {
    currentStack = currentStack!.parent;
  }
  for (final frame in diff.newFrames) {
    currentStack = StateStackImpl.pushFrame(currentStack, frame);
  }
  return currentStack;
}
