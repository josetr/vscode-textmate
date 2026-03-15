import 'dart:io';
import 'dart:typed_data';

import 'package:wasm_run/wasm_run.dart';

Future<void> main() async {
  final wasmPath = File('../node_modules/vscode-oniguruma/release/onig.wasm');
  final bytes = Uint8List.fromList(await wasmPath.readAsBytes());
  final module = await compileWasmModule(bytes);

  stdout.writeln('Imports:');
  for (final import in module.getImports()) {
    final type = import.type;
    final description = type == null
        ? 'type=null'
        : type.when(
            func: (func) => 'params=${func.parameters} results=${func.results}',
            global: (global) => '$global',
            memory: (memory) => '$memory',
            table: (table) => '$table',
          );
    stdout.writeln(
      '${import.module}::${import.name} ${import.kind} $description',
    );
  }

  stdout.writeln('Exports:');
  for (final export in module.getExports()) {
    stdout.writeln('${export.name} ${export.kind} ${export.type}');
  }
}
