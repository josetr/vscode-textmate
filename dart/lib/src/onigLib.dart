import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:wasm_run/wasm_run.dart';

class FindOption {
  static const int none = 0;
  static const int notBeginString = 1;
  static const int notEndString = 2;
  static const int notBeginPosition = 4;
  static const int debugCall = 8;
}

class OnigCaptureIndex {
  const OnigCaptureIndex({
    required this.start,
    required this.end,
    required this.length,
  });

  final int start;
  final int end;
  final int length;
}

class OnigMatch {
  const OnigMatch({required this.index, required this.captureIndices});

  final int index;
  final List<OnigCaptureIndex> captureIndices;
}

abstract class OnigScanner {
  OnigMatch? findNextMatchSync(
    StringOrOnigString string,
    int startPosition,
    int options,
  );

  void dispose();
}

abstract class OnigString {
  String get content;

  void dispose();
}

typedef StringOrOnigString = Object;

abstract class OnigLib {
  OnigScanner createOnigScanner(List<String> sources);

  OnigString createOnigString(String value);
}

void disposeOnigString(OnigString value) {
  value.dispose();
}

Future<OnigLib> loadOnigWasm({String? wasmPath}) async {
  final path =
      wasmPath ??
      File(
        '${Directory.current.path}/../node_modules/vscode-oniguruma/release/onig.wasm',
      ).absolute.path;
  final bytes = Uint8List.fromList(await File(path).readAsBytes());
  final module = await compileWasmModule(bytes);
  final builder = module.builder();

  late WasmInstance instance;
  late WasmMemory memory;

  builder
    ..addImport(
      'env',
      'emscripten_memcpy_big',
      WasmFunction.voidReturn((int dest, int src, int num) {
        memory.view.setRange(dest, dest + num, memory.view, src);
      }, params: const [ValueTy.i32, ValueTy.i32, ValueTy.i32]),
    )
    ..addImport(
      'env',
      'emscripten_get_now',
      WasmFunction(
        () => DateTime.now().millisecondsSinceEpoch.toDouble(),
        params: const [],
        results: const [ValueTy.f64],
      ),
    )
    ..addImport(
      'wasi_snapshot_preview1',
      'fd_write',
      WasmFunction(
        (int fd, int iovs, int iovsLen, int pnum) {
          final data = ByteData.sublistView(memory.view);
          var written = 0;
          final chunks = <int>[];
          for (var i = 0; i < iovsLen; i++) {
            final ptr = data.getUint32(iovs + (i * 8), Endian.little);
            final len = data.getUint32(iovs + (i * 8) + 4, Endian.little);
            chunks.addAll(memory.view.sublist(ptr, ptr + len));
            written += len;
          }
          if (fd == 1) {
            stdout.write(utf8.decode(chunks, allowMalformed: true));
          } else if (fd == 2) {
            stderr.write(utf8.decode(chunks, allowMalformed: true));
          }
          data.setUint32(pnum, written, Endian.little);
          return 0;
        },
        params: const [ValueTy.i32, ValueTy.i32, ValueTy.i32, ValueTy.i32],
        results: const [ValueTy.i32],
      ),
    )
    ..addImport(
      'env',
      'emscripten_resize_heap',
      WasmFunction(
        (int requestedSize) {
          if (requestedSize <= memory.lengthInBytes) {
            return 1;
          }
          final currentPages = memory.lengthInPages;
          final requestedPages =
              ((requestedSize + WasmMemory.bytesPerPage - 1) ~/
                  WasmMemory.bytesPerPage) -
              currentPages;
          if (requestedPages > 0) {
            memory.grow(requestedPages);
          }
          return 1;
        },
        params: const [ValueTy.i32],
        results: const [ValueTy.i32],
      ),
    );

  instance = await builder.build();
  memory = instance.getMemory('memory')!;
  return _OnigWasmLib(instance, memory);
}

class _OnigWasmLib implements OnigLib {
  _OnigWasmLib(WasmInstance instance, this._memory)
    : _malloc = instance.getFunction('omalloc')!,
      _free = instance.getFunction('ofree')!,
      _getLastOnigError = instance.getFunction('getLastOnigError')!,
      _createOnigScannerFn = instance.getFunction('createOnigScanner')!,
      _freeOnigScannerFn = instance.getFunction('freeOnigScanner')!,
      _findNextOnigScannerMatchFn = instance.getFunction(
        'findNextOnigScannerMatch',
      )!,
      _findNextOnigScannerMatchDbgFn = instance.getFunction(
        'findNextOnigScannerMatchDbg',
      )!;

  final WasmMemory _memory;
  final WasmFunction _malloc;
  final WasmFunction _free;
  final WasmFunction _getLastOnigError;
  final WasmFunction _createOnigScannerFn;
  final WasmFunction _freeOnigScannerFn;
  final WasmFunction _findNextOnigScannerMatchFn;
  final WasmFunction _findNextOnigScannerMatchDbgFn;

  int malloc(int bytes) => _malloc([bytes]).first! as int;

  void free(int pointer) {
    _free([pointer]);
  }

  String readCString(int pointer) {
    final bytes = <int>[];
    var cursor = pointer;
    while (_memory.view[cursor] != 0) {
      bytes.add(_memory.view[cursor]);
      cursor++;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  OnigScanner createOnigScanner(List<String> sources) {
    return _OnigWasmScanner(this, sources);
  }

  @override
  OnigString createOnigString(String value) {
    return _OnigWasmString(this, value);
  }
}

class _UtfString {
  _UtfString(String value)
    : utf16Length = value.length,
      utf16Value = value,
      utf8Value = utf8.encode(value) {
    utf8Length = utf8Value.length;
    if (utf8Length != utf16Length) {
      utf16OffsetToUtf8 = Uint32List(utf16Length + 1);
      utf8OffsetToUtf16 = Uint32List(utf8Length + 1);
      utf16OffsetToUtf8![utf16Length] = utf8Length;
      utf8OffsetToUtf16![utf8Length] = utf16Length;

      var utf8Offset = 0;
      for (var utf16Offset = 0; utf16Offset < value.length; utf16Offset++) {
        final rune = value.runes.elementAt(
          utf16Offset == 0 ? 0 : value.substring(0, utf16Offset).runes.length,
        );
        final bytes = utf8.encode(String.fromCharCode(rune));
        utf16OffsetToUtf8![utf16Offset] = utf8Offset;
        for (var i = 0; i < bytes.length; i++) {
          utf8OffsetToUtf16![utf8Offset + i] = utf16Offset;
        }
        if (rune > 0xffff && utf16Offset + 1 < value.length) {
          utf16Offset++;
          utf16OffsetToUtf8![utf16Offset] = utf8Offset;
        }
        utf8Offset += bytes.length;
      }
    }
  }

  final int utf16Length;
  late final int utf8Length;
  final String utf16Value;
  final List<int> utf8Value;
  Uint32List? utf16OffsetToUtf8;
  Uint32List? utf8OffsetToUtf16;

  int createString(_OnigWasmLib lib) {
    final pointer = lib.malloc(utf8Length);
    lib._memory.view.setRange(pointer, pointer + utf8Length, utf8Value);
    return pointer;
  }
}

class _OnigWasmString implements OnigString {
  _OnigWasmString(this._lib, this.content)
    : id = ++_lastId,
      _utfString = _UtfString(content) {
    if (_utfString.utf8Length < 10000 && !_sharedPointerInUse) {
      _sharedPointer ??= _lib.malloc(10000);
      _sharedPointerInUse = true;
      _lib._memory.view.setRange(
        _sharedPointer!,
        _sharedPointer! + _utfString.utf8Length,
        _utfString.utf8Value,
      );
      pointer = _sharedPointer!;
    } else {
      pointer = _utfString.createString(_lib);
    }
  }

  static int _lastId = 0;
  static int? _sharedPointer;
  static bool _sharedPointerInUse = false;

  final _OnigWasmLib _lib;
  @override
  final String content;
  final int id;
  final _UtfString _utfString;
  late final int pointer;

  int get utf8Length => _utfString.utf8Length;

  int convertUtf8OffsetToUtf16(int value) {
    if (value == 0xffffffff) {
      return 0;
    }
    final offsets = _utfString.utf8OffsetToUtf16;
    if (offsets == null) {
      return value;
    }
    if (value < 0) {
      return 0;
    }
    if (value > utf8Length) {
      return _utfString.utf16Length;
    }
    return offsets[value];
  }

  int convertUtf16OffsetToUtf8(int value) {
    if (value == 0xffffffff) {
      return 0;
    }
    final offsets = _utfString.utf16OffsetToUtf8;
    if (offsets == null) {
      return value;
    }
    if (value < 0) {
      return 0;
    }
    if (value > _utfString.utf16Length) {
      return utf8Length;
    }
    return offsets[value];
  }

  @override
  void dispose() {
    if (_sharedPointer != null && pointer == _sharedPointer) {
      _sharedPointerInUse = false;
    } else {
      _lib.free(pointer);
    }
  }
}

class _OnigWasmScanner implements OnigScanner {
  _OnigWasmScanner(this._lib, List<String> patterns) {
    final pointers = <int>[];
    final lengths = <int>[];
    try {
      for (final pattern in patterns) {
        final utfString = _UtfString(pattern);
        pointers.add(utfString.createString(_lib));
        lengths.add(utfString.utf8Length);
      }

      final pointerArray = _lib.malloc(patterns.length * 4);
      final lengthArray = _lib.malloc(patterns.length * 4);
      final data = ByteData.sublistView(_lib._memory.view);
      for (var i = 0; i < patterns.length; i++) {
        data.setUint32(pointerArray + (i * 4), pointers[i], Endian.little);
        data.setUint32(lengthArray + (i * 4), lengths[i], Endian.little);
      }
      final result =
          _lib._createOnigScannerFn([
                pointerArray,
                lengthArray,
                patterns.length,
              ]).first!
              as int;
      _pointer = result;
      _lib.free(pointerArray);
      _lib.free(lengthArray);

      if (_pointer == 0) {
        throw StateError(
          _lib.readCString(_lib._getLastOnigError([]).first! as int),
        );
      }
    } finally {
      for (final pointer in pointers) {
        _lib.free(pointer);
      }
    }
  }

  final _OnigWasmLib _lib;
  late final int _pointer;

  @override
  OnigMatch? findNextMatchSync(
    StringOrOnigString string,
    int startPosition,
    int options,
  ) {
    final debugCall = (options & FindOption.debugCall) != 0;
    final onigString = string is _OnigWasmString
        ? string
        : _OnigWasmString(_lib, string as String);
    final shouldDispose = string is! _OnigWasmString;

    try {
      final resultPointer =
          (debugCall
                      ? _lib._findNextOnigScannerMatchDbgFn
                      : _lib._findNextOnigScannerMatchFn)([
                    _pointer,
                    onigString.id,
                    onigString.pointer,
                    onigString.utf8Length,
                    onigString.convertUtf16OffsetToUtf8(startPosition),
                    options,
                  ])
                  .first!
              as int;

      if (resultPointer == 0) {
        return null;
      }

      final data = ByteData.sublistView(_lib._memory.view);
      var offset = resultPointer;
      final index = data.getUint32(offset, Endian.little);
      offset += 4;
      final count = data.getUint32(offset, Endian.little);
      offset += 4;

      final captures = <OnigCaptureIndex>[];
      for (var i = 0; i < count; i++) {
        final start = onigString.convertUtf8OffsetToUtf16(
          data.getUint32(offset, Endian.little),
        );
        offset += 4;
        final end = onigString.convertUtf8OffsetToUtf16(
          data.getUint32(offset, Endian.little),
        );
        offset += 4;
        captures.add(
          OnigCaptureIndex(start: start, end: end, length: end - start),
        );
      }

      return OnigMatch(index: index, captureIndices: captures);
    } finally {
      if (shouldDispose) {
        onigString.dispose();
      }
    }
  }

  @override
  void dispose() {
    _lib._freeOnigScannerFn([_pointer]);
  }
}
