import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../core/logger.dart';

/// 尝试查找符号，支持带下划线和不带下划线两种形式
/// 返回符号名字，用于 lookupFunction
String _resolveSymbolName(ffi.DynamicLibrary lib, String name) {
  // 首先尝试带下划线的名字（Windows __cdecl 约定）
  if (Platform.isWindows) {
    try {
      lib.lookup<ffi.NativeFunction<ffi.Pointer<ffi.Void> Function()>>(
        '_$name',
      );
      return '_$name';
    } catch (_) {
      // 如果失败，尝试不带下划线的名字
    }
  }
  // 验证符号是否存在
  try {
    lib.lookup<ffi.NativeFunction<ffi.Pointer<ffi.Void> Function()>>(name);
    return name;
  } catch (e) {
    Logger.w('Symbol $name not found in library: $e', tag: 'ZstdService');
    rethrow;
  }
}

/// zstd 库加载
/// 首先尝试从静态链接的可执行文件中查找符号
/// 如果找不到，则尝试加载动态库
ffi.DynamicLibrary _openZstdLibrary() {
  Logger.i('Attempting to load zstd library...', tag: 'ZstdService');

  // Android 平台优先尝试加载 libzstd.so
  if (Platform.isAndroid) {
    Logger.i(
      'Android platform detected, trying to load zstd library...',
      tag: 'ZstdService',
    );

    // 首先尝试加载独立的 libzstd.so
    try {
      final lib = ffi.DynamicLibrary.open('libzstd.so');
      // 验证符号存在
      _resolveSymbolName(lib, 'ZSTD_createDCtx');
      Logger.i('Successfully loaded libzstd.so', tag: 'ZstdService');
      return lib;
    } catch (e) {
      Logger.w(
        'Failed to load libzstd.so: $e, trying process library...',
        tag: 'ZstdService',
      );
    }

    // 尝试从进程库加载（静态链接的情况）
    try {
      final processLib = ffi.DynamicLibrary.process();
      _resolveSymbolName(processLib, 'ZSTD_createDCtx');
      Logger.i('Found zstd symbols in process library', tag: 'ZstdService');
      return processLib;
    } catch (e) {
      Logger.e(
        'Failed to find zstd in process library: $e',
        tag: 'ZstdService',
      );
    }

    // 最后尝试从可执行文件加载
    try {
      final execLib = ffi.DynamicLibrary.executable();
      _resolveSymbolName(execLib, 'ZSTD_createDCtx');
      Logger.i('Found zstd symbols in executable', tag: 'ZstdService');
      return execLib;
    } catch (e) {
      Logger.e('Failed to find zstd in executable: $e', tag: 'ZstdService');
    }

    throw Exception(
      'Could not load zstd library on Android. Please check if libzstd.so is properly built and included in the APK.',
    );
  }

  // 首先尝试从当前进程中查找（静态链接的情况）
  try {
    final processLib = ffi.DynamicLibrary.process();
    // 尝试查找一个 zstd 函数来验证
    final symbolName = _resolveSymbolName(processLib, 'ZSTD_createDCtx');
    Logger.i('Found zstd symbol in process: $symbolName', tag: 'ZstdService');
    Logger.i('Using statically linked zstd from process', tag: 'ZstdService');
    return processLib;
  } catch (e) {
    Logger.w('Failed to find zstd in process: $e', tag: 'ZstdService');
  }

  // 尝试从可执行文件中查找
  try {
    final executableLib = ffi.DynamicLibrary.executable();
    final symbolName = _resolveSymbolName(executableLib, 'ZSTD_createDCtx');
    Logger.i(
      'Found zstd symbol in executable: $symbolName',
      tag: 'ZstdService',
    );
    Logger.i(
      'Using statically linked zstd from executable',
      tag: 'ZstdService',
    );
    return executableLib;
  } catch (e) {
    Logger.w('Failed to find zstd in executable: $e', tag: 'ZstdService');
  }

  // 尝试加载动态库
  if (Platform.isWindows) {
    final possiblePaths = [
      'libzstd.dll',
      'zstd.dll',
      '${Platform.environment['SYSTEMROOT'] ?? r'C:\Windows'}\System32\libzstd.dll',
      '${Platform.environment['SYSTEMROOT'] ?? r'C:\Windows'}\SysWOW64\libzstd.dll',
    ];
    for (final path in possiblePaths) {
      Logger.i('Trying to load zstd from: $path', tag: 'ZstdService');
      try {
        final lib = ffi.DynamicLibrary.open(path);
        Logger.i('Successfully loaded zstd from: $path', tag: 'ZstdService');
        return lib;
      } catch (e) {
        Logger.w('Failed to load zstd from $path: $e', tag: 'ZstdService');
        continue;
      }
    }
    Logger.e('Could not find zstd library in any location', tag: 'ZstdService');
    throw Exception(
      'Could not find zstd library. Please ensure zstd is statically linked or libzstd.dll is available.',
    );
  } else if (Platform.isLinux) {
    try {
      return ffi.DynamicLibrary.open('libzstd.so');
    } catch (e) {
      Logger.e('Failed to load libzstd.so: $e', tag: 'ZstdService');
      throw Exception(
        'Could not find libzstd.so. Please ensure zstd is statically linked or libzstd.so is available.',
      );
    }
  } else if (Platform.isMacOS) {
    try {
      return ffi.DynamicLibrary.open('libzstd.dylib');
    } catch (e) {
      Logger.e('Failed to load libzstd.dylib: $e', tag: 'ZstdService');
      throw Exception(
        'Could not find libzstd.dylib. Please ensure zstd is statically linked or libzstd.dylib is available.',
      );
    }
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

late final ffi.DynamicLibrary _zstdLib;
bool _isLibraryLoaded = false;
bool _ffibindingsInitialized = false;

/// 初始化 zstd 库
void _ensureLibraryLoaded() {
  if (_isLibraryLoaded) return;
  try {
    _zstdLib = _openZstdLibrary();
    _isLibraryLoaded = true;
    Logger.i('Zstd library loaded successfully', tag: 'ZstdService');
  } catch (e) {
    Logger.w('Failed to load zstd FFI library: $e', tag: 'ZstdService');
  }
}

void _tryInitializeBindings() {
  Logger.i(
    '_tryInitializeBindings called, _isLibraryLoaded=$_isLibraryLoaded',
    tag: 'ZstdService',
  );
  if (!_isLibraryLoaded) {
    Logger.i('Calling _ensureLibraryLoaded()', tag: 'ZstdService');
    _ensureLibraryLoaded();
  }
  Logger.i(
    'After _ensureLibraryLoaded, _isLibraryLoaded=$_isLibraryLoaded',
    tag: 'ZstdService',
  );
  if (!_isLibraryLoaded) {
    Logger.w(
      'Zstd FFI library not available, all compression disabled',
      tag: 'ZstdService',
    );
    _supportsDictCompression = false;
    return;
  }
  try {
    _initializeBindingsInternal();
    Logger.i(
      'Zstd FFI bindings initialized successfully, _supportsDictCompression=$_supportsDictCompression',
      tag: 'ZstdService',
    );
  } catch (e, stackTrace) {
    Logger.e(
      'Failed to initialize zstd FFI bindings: $e',
      tag: 'ZstdService',
      error: e,
      stackTrace: stackTrace,
    );
    _supportsDictCompression = false;
  }
}

// FFI 函数签名和加载
// 解压相关
typedef ZstdCreateDDictNative =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef ZstdCreateDDictDart =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint8>, int);

late final ZstdCreateDDictDart _zstdCreateDDict;

typedef ZstdFreeDDictNative = ffi.UintPtr Function(ffi.Pointer<ffi.Void>);
typedef ZstdFreeDDictDart = int Function(ffi.Pointer<ffi.Void>);

late final ZstdFreeDDictDart _zstdFreeDDict;

typedef ZstdCreateDCtxNative = ffi.Pointer<ffi.Void> Function();
typedef ZstdCreateDCtxDart = ffi.Pointer<ffi.Void> Function();

late final ZstdCreateDCtxDart _zstdCreateDCtx;

typedef ZstdFreeDCtxNative = ffi.UintPtr Function(ffi.Pointer<ffi.Void>);
typedef ZstdFreeDCtxDart = int Function(ffi.Pointer<ffi.Void>);

late final ZstdFreeDCtxDart _zstdFreeDCtx;

typedef ZstdDecompressUsingDDictNative =
    ffi.IntPtr Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.IntPtr,
      ffi.Pointer<ffi.Uint8>,
      ffi.IntPtr,
      ffi.Pointer<ffi.Void>,
    );
typedef ZstdDecompressUsingDDictDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Void>,
    );

late final ZstdDecompressUsingDDictDart _zstdDecompressUsingDDict;

typedef ZstdGetFrameContentSizeNative =
    ffi.Uint64 Function(ffi.Pointer<ffi.Uint8>, ffi.IntPtr);
typedef ZstdGetFrameContentSizeDart = int Function(ffi.Pointer<ffi.Uint8>, int);

late final ZstdGetFrameContentSizeDart _zstdGetFrameContentSize;

typedef ZstdIsErrorNative = ffi.Uint32 Function(ffi.UintPtr);
typedef ZstdIsErrorDart = int Function(int);

late final ZstdIsErrorDart _zstdIsError;

typedef ZstdGetErrorNameNative = ffi.Pointer<Utf8> Function(ffi.UintPtr);
typedef ZstdGetErrorNameDart = ffi.Pointer<Utf8> Function(int);

late final ZstdGetErrorNameDart _zstdGetErrorName;

// 压缩相关
typedef ZstdCreateCDictNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.IntPtr,
      ffi.Int32,
    );
typedef ZstdCreateCDictDart =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint8>, int, int);

late final ZstdCreateCDictDart _zstdCreateCDict;

typedef ZstdFreeCDictNative = ffi.UintPtr Function(ffi.Pointer<ffi.Void>);
typedef ZstdFreeCDictDart = int Function(ffi.Pointer<ffi.Void>);

late final ZstdFreeCDictDart _zstdFreeCDict;

typedef ZstdCreateCCtxNative = ffi.Pointer<ffi.Void> Function();
typedef ZstdCreateCCtxDart = ffi.Pointer<ffi.Void> Function();

late final ZstdCreateCCtxDart _zstdCreateCCtx;

typedef ZstdFreeCCtxNative = ffi.UintPtr Function(ffi.Pointer<ffi.Void>);
typedef ZstdFreeCCtxDart = int Function(ffi.Pointer<ffi.Void>);

late final ZstdFreeCCtxDart _zstdFreeCCtx;

typedef ZstdCompressUsingCDictNative =
    ffi.IntPtr Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.IntPtr,
      ffi.Pointer<ffi.Uint8>,
      ffi.IntPtr,
      ffi.Pointer<ffi.Void>,
    );
typedef ZstdCompressUsingCDictDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Void>,
    );

late final ZstdCompressUsingCDictDart _zstdCompressUsingCDict;

typedef ZstdCompressBoundNative = ffi.UintPtr Function(ffi.IntPtr);
typedef ZstdCompressBoundDart = int Function(int);

late final ZstdCompressBoundDart _zstdCompressBound;

// 不使用字典的压缩/解压函数
typedef ZstdDecompressNative =
    ffi.IntPtr Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.IntPtr,
      ffi.Pointer<ffi.Uint8>,
      ffi.IntPtr,
    );
typedef ZstdDecompressDart =
    int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint8>, int);

late final ZstdDecompressDart _zstdDecompress;

typedef ZstdCompressNative =
    ffi.IntPtr Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.IntPtr,
      ffi.Pointer<ffi.Uint8>,
      ffi.IntPtr,
      ffi.Int32,
    );
typedef ZstdCompressDart =
    int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint8>, int, int);

late final ZstdCompressDart _zstdCompress;

// 错误码常量
const int zstdContentSizeError = -2;
const int zstdContentSizeUnknown = -1;

// 检查是否支持字典压缩功能
bool _supportsDictCompression = false;

bool _checkError(int code) => _zstdIsError(code) != 0;

String _getErrorName(int code) => _zstdGetErrorName(code).toDartString();

bool _initializeDictBindings() {
  final symbols = [
    'ZSTD_createDDict',
    'ZSTD_freeDDict',
    'ZSTD_decompress_usingDDict',
    'ZSTD_createCDict',
    'ZSTD_freeCDict',
    'ZSTD_compress_usingCDict',
  ];

  for (final symbol in symbols) {
    try {
      final resolvedName = _resolveSymbolName(_zstdLib, symbol);
      Logger.d(
        'Looking up symbol: $symbol -> $resolvedName',
        tag: 'ZstdService',
      );
      _zstdLib.lookup<ffi.NativeFunction<ffi.Pointer<ffi.Void> Function()>>(
        resolvedName,
      );
      Logger.d('Symbol found: $resolvedName', tag: 'ZstdService');
    } catch (e) {
      Logger.w('Symbol not found: $symbol, error: $e', tag: 'ZstdService');
    }
  }

  try {
    _zstdCreateDDict = _zstdLib
        .lookupFunction<ZstdCreateDDictNative, ZstdCreateDDictDart>(
          _resolveSymbolName(_zstdLib, 'ZSTD_createDDict'),
        );
    Logger.d('ZSTD_createDDict bound successfully', tag: 'ZstdService');

    _zstdFreeDDict = _zstdLib
        .lookupFunction<ZstdFreeDDictNative, ZstdFreeDDictDart>(
          _resolveSymbolName(_zstdLib, 'ZSTD_freeDDict'),
        );
    Logger.d('ZSTD_freeDDict bound successfully', tag: 'ZstdService');

    _zstdDecompressUsingDDict = _zstdLib
        .lookupFunction<
          ZstdDecompressUsingDDictNative,
          ZstdDecompressUsingDDictDart
        >(_resolveSymbolName(_zstdLib, 'ZSTD_decompress_usingDDict'));
    Logger.d(
      'ZSTD_decompress_usingDDict bound successfully',
      tag: 'ZstdService',
    );

    _zstdCreateCDict = _zstdLib
        .lookupFunction<ZstdCreateCDictNative, ZstdCreateCDictDart>(
          _resolveSymbolName(_zstdLib, 'ZSTD_createCDict'),
        );
    Logger.d('ZSTD_createCDict bound successfully', tag: 'ZstdService');

    _zstdFreeCDict = _zstdLib
        .lookupFunction<ZstdFreeCDictNative, ZstdFreeCDictDart>(
          _resolveSymbolName(_zstdLib, 'ZSTD_freeCDict'),
        );
    Logger.d('ZSTD_freeCDict bound successfully', tag: 'ZstdService');

    _zstdCompressUsingCDict = _zstdLib
        .lookupFunction<
          ZstdCompressUsingCDictNative,
          ZstdCompressUsingCDictDart
        >(_resolveSymbolName(_zstdLib, 'ZSTD_compress_usingCDict'));
    Logger.d('ZSTD_compress_usingCDict bound successfully', tag: 'ZstdService');

    Logger.i(
      'All dictionary bindings initialized successfully',
      tag: 'ZstdService',
    );
    return true;
  } catch (e, stackTrace) {
    Logger.e(
      'Zstd dictionary compression not supported: $e',
      tag: 'ZstdService',
      error: e,
      stackTrace: stackTrace,
    );
    return false;
  }
}

void _initializeBindingsInternal() {
  _zstdCreateDCtx = _zstdLib
      .lookupFunction<ZstdCreateDCtxNative, ZstdCreateDCtxDart>(
        _resolveSymbolName(_zstdLib, 'ZSTD_createDCtx'),
      );
  _zstdFreeDCtx = _zstdLib.lookupFunction<ZstdFreeDCtxNative, ZstdFreeDCtxDart>(
    _resolveSymbolName(_zstdLib, 'ZSTD_freeDCtx'),
  );
  _zstdGetFrameContentSize = _zstdLib
      .lookupFunction<
        ZstdGetFrameContentSizeNative,
        ZstdGetFrameContentSizeDart
      >(_resolveSymbolName(_zstdLib, 'ZSTD_getFrameContentSize'));
  _zstdIsError = _zstdLib.lookupFunction<ZstdIsErrorNative, ZstdIsErrorDart>(
    _resolveSymbolName(_zstdLib, 'ZSTD_isError'),
  );
  _zstdGetErrorName = _zstdLib
      .lookupFunction<ZstdGetErrorNameNative, ZstdGetErrorNameDart>(
        _resolveSymbolName(_zstdLib, 'ZSTD_getErrorName'),
      );
  _zstdCreateCCtx = _zstdLib
      .lookupFunction<ZstdCreateCCtxNative, ZstdCreateCCtxDart>(
        _resolveSymbolName(_zstdLib, 'ZSTD_createCCtx'),
      );
  _zstdFreeCCtx = _zstdLib.lookupFunction<ZstdFreeCCtxNative, ZstdFreeCCtxDart>(
    _resolveSymbolName(_zstdLib, 'ZSTD_freeCCtx'),
  );
  _zstdCompressBound = _zstdLib
      .lookupFunction<ZstdCompressBoundNative, ZstdCompressBoundDart>(
        _resolveSymbolName(_zstdLib, 'ZSTD_compressBound'),
      );
  _zstdDecompress = _zstdLib
      .lookupFunction<ZstdDecompressNative, ZstdDecompressDart>(
        _resolveSymbolName(_zstdLib, 'ZSTD_decompress'),
      );
  _zstdCompress = _zstdLib.lookupFunction<ZstdCompressNative, ZstdCompressDart>(
    _resolveSymbolName(_zstdLib, 'ZSTD_compress'),
  );

  _supportsDictCompression = _initializeDictBindings();
}

/// Zstd 压缩/解压服务类
class ZstdService {
  static final ZstdService _instance = ZstdService._internal();
  factory ZstdService() => _instance;
  ZstdService._internal() {
    _tryInitializeBindings();
  }

  /// 使用字典解压数据
  Uint8List decompressWithDict(Uint8List compressedData, Uint8List dictBytes) {
    if (compressedData.isEmpty) {
      throw ArgumentError('Compressed data is empty');
    }
    if (dictBytes.isEmpty) {
      throw ArgumentError('Dictionary is empty');
    }

    final dictPtr = calloc<ffi.Uint8>(dictBytes.length);
    try {
      dictPtr.asTypedList(dictBytes.length).setAll(0, dictBytes);
      final ddict = _zstdCreateDDict(dictPtr, dictBytes.length);
      if (ddict == ffi.nullptr) {
        throw Exception('Failed to create ZSTD decompression dictionary');
      }

      try {
        final dctx = _zstdCreateDCtx();
        if (dctx == ffi.nullptr) {
          throw Exception('Failed to create ZSTD decompression context');
        }

        try {
          final compressedPtr = calloc<ffi.Uint8>(compressedData.length);
          late int originalSize;
          try {
            compressedPtr
                .asTypedList(compressedData.length)
                .setAll(0, compressedData);
            originalSize = _zstdGetFrameContentSize(
              compressedPtr,
              compressedData.length,
            );
          } finally {
            calloc.free(compressedPtr);
          }

          if (originalSize == zstdContentSizeError) {
            throw Exception('Failed to get frame content size');
          }
          if (originalSize == zstdContentSizeUnknown) {
            originalSize = compressedData.length * 10;
          }

          final dstPtr = calloc<ffi.Uint8>(originalSize);
          try {
            final srcPtr = calloc<ffi.Uint8>(compressedData.length);
            try {
              srcPtr
                  .asTypedList(compressedData.length)
                  .setAll(0, compressedData);

              final result = _zstdDecompressUsingDDict(
                dctx,
                dstPtr,
                originalSize,
                srcPtr,
                compressedData.length,
                ddict,
              );

              if (_checkError(result)) {
                throw Exception(
                  'ZSTD decompression failed: ${_getErrorName(result)}',
                );
              }

              final output = Uint8List(result);
              output.setAll(0, dstPtr.asTypedList(result));
              return output;
            } finally {
              calloc.free(srcPtr);
            }
          } finally {
            calloc.free(dstPtr);
          }
        } finally {
          _zstdFreeDCtx(dctx);
        }
      } finally {
        _zstdFreeDDict(ddict);
      }
    } finally {
      calloc.free(dictPtr);
    }
  }

  /// 使用字典压缩数据
  Uint8List compressWithDict(
    Uint8List data,
    Uint8List dictBytes, {
    int level = 3,
  }) {
    if (data.isEmpty) {
      throw ArgumentError('Data is empty');
    }
    if (dictBytes.isEmpty) {
      throw ArgumentError('Dictionary is empty');
    }

    final dictPtr = calloc<ffi.Uint8>(dictBytes.length);
    try {
      dictPtr.asTypedList(dictBytes.length).setAll(0, dictBytes);
      final cdict = _zstdCreateCDict(dictPtr, dictBytes.length, level);
      if (cdict == ffi.nullptr) {
        throw Exception('Failed to create ZSTD compression dictionary');
      }

      try {
        final cctx = _zstdCreateCCtx();
        if (cctx == ffi.nullptr) {
          throw Exception('Failed to create ZSTD compression context');
        }

        try {
          final maxCompressedSize = _zstdCompressBound(data.length);
          final dstPtr = calloc<ffi.Uint8>(maxCompressedSize);
          try {
            final srcPtr = calloc<ffi.Uint8>(data.length);
            try {
              srcPtr.asTypedList(data.length).setAll(0, data);

              final result = _zstdCompressUsingCDict(
                cctx,
                dstPtr,
                maxCompressedSize,
                srcPtr,
                data.length,
                cdict,
              );

              if (_checkError(result)) {
                throw Exception(
                  'ZSTD compression failed: ${_getErrorName(result)}',
                );
              }

              final output = Uint8List(result);
              output.setAll(0, dstPtr.asTypedList(result));
              return output;
            } finally {
              calloc.free(srcPtr);
            }
          } finally {
            calloc.free(dstPtr);
          }
        } finally {
          _zstdFreeCCtx(cctx);
        }
      } finally {
        _zstdFreeCDict(cdict);
      }
    } finally {
      calloc.free(dictPtr);
    }
  }

  /// 不使用字典解压（使用 FFI 调用静态链接的 zstd 库）
  Uint8List decompressWithoutDict(Uint8List compressedData) {
    Logger.d(
      'decompressWithoutDict called: compressedData.length=${compressedData.length}',
      tag: 'ZstdService',
    );
    if (compressedData.isEmpty) {
      throw ArgumentError('Compressed data is empty');
    }

    final compressedPtr = calloc<ffi.Uint8>(compressedData.length);
    try {
      compressedPtr
          .asTypedList(compressedData.length)
          .setAll(0, compressedData);

      final originalSize = _zstdGetFrameContentSize(
        compressedPtr,
        compressedData.length,
      );
      Logger.d(
        'decompressWithoutDict: originalSize=$originalSize',
        tag: 'ZstdService',
      );

      if (originalSize == zstdContentSizeError ||
          originalSize == zstdContentSizeUnknown) {
        throw Exception(
          'Failed to get decompressed size: originalSize=$originalSize',
        );
      }

      final decompressedPtr = calloc<ffi.Uint8>(originalSize);
      try {
        final result = _zstdDecompress(
          decompressedPtr,
          originalSize,
          compressedPtr,
          compressedData.length,
        );
        Logger.d(
          'decompressWithoutDict: ZSTD_decompress result=$result',
          tag: 'ZstdService',
        );

        if (_checkError(result)) {
          throw Exception('Decompression failed: ${_getErrorName(result)}');
        }

        return Uint8List.fromList(decompressedPtr.asTypedList(result));
      } finally {
        calloc.free(decompressedPtr);
      }
    } finally {
      calloc.free(compressedPtr);
    }
  }

  /// 不使用字典压缩（使用 FFI 调用静态链接的 zstd 库）
  Uint8List compressWithoutDict(Uint8List data, {int level = 3}) {
    Logger.d(
      'compressWithoutDict called: data.length=${data.length}, level=$level',
      tag: 'ZstdService',
    );
    if (data.isEmpty) {
      throw ArgumentError('Data is empty');
    }

    final srcPtr = calloc<ffi.Uint8>(data.length);
    try {
      srcPtr.asTypedList(data.length).setAll(0, data);

      final maxDstSize = _zstdCompressBound(data.length);
      Logger.d(
        'compressWithoutDict: maxDstSize=$maxDstSize',
        tag: 'ZstdService',
      );
      final dstPtr = calloc<ffi.Uint8>(maxDstSize);
      try {
        final result = _zstdCompress(
          dstPtr,
          maxDstSize,
          srcPtr,
          data.length,
          level,
        );
        Logger.d(
          'compressWithoutDict: ZSTD_compress result=$result',
          tag: 'ZstdService',
        );

        if (_checkError(result)) {
          throw Exception('Compression failed: ${_getErrorName(result)}');
        }

        return Uint8List.fromList(dstPtr.asTypedList(result));
      } finally {
        calloc.free(dstPtr);
      }
    } finally {
      calloc.free(srcPtr);
    }
  }

  /// 解压数据，如果有字典则使用字典解压，否则不使用字典
  Uint8List decompress(Uint8List compressedData, Uint8List? dictBytes) {
    Logger.d(
      'decompress called: compressedData.length=${compressedData.length}, dictBytes=${dictBytes?.length ?? 'null'}, _supportsDictCompression=$_supportsDictCompression',
      tag: 'ZstdService',
    );
    if (dictBytes != null && dictBytes.isNotEmpty) {
      if (!_supportsDictCompression) {
        throw Exception(
          'Zstd dictionary compression is not supported on this platform. '
          'Please ensure zstd library with dictionary support is properly linked.',
        );
      }
      Logger.d('Using decompressWithDict', tag: 'ZstdService');
      return decompressWithDict(compressedData, dictBytes);
    } else {
      Logger.d('Using decompressWithoutDict', tag: 'ZstdService');
      return decompressWithoutDict(compressedData);
    }
  }

  /// 压缩数据，如果有字典则使用字典压缩，否则不使用字典
  Uint8List compress(Uint8List data, Uint8List? dictBytes, {int level = 3}) {
    Logger.d(
      'compress called: data.length=${data.length}, dictBytes=${dictBytes?.length ?? 'null'}, _supportsDictCompression=$_supportsDictCompression',
      tag: 'ZstdService',
    );
    if (dictBytes != null && dictBytes.isNotEmpty) {
      if (!_supportsDictCompression) {
        throw Exception(
          'Zstd dictionary compression is not supported on this platform. '
          'Please ensure zstd library with dictionary support is properly linked.',
        );
      }
      Logger.d('Using compressWithDict', tag: 'ZstdService');
      return compressWithDict(data, dictBytes, level: level);
    } else {
      Logger.d('Using compressWithoutDict', tag: 'ZstdService');
      return compressWithoutDict(data, level: level);
    }
  }
}
