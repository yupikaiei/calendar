import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _MlcEngineCreateNative = Int32 Function(Pointer<Utf8> modelPath);
typedef _MlcEngineCreateDart = int Function(Pointer<Utf8> modelPath);
typedef _MlcEngineDestroyNative = Void Function(Int32 handle);
typedef _MlcEngineDestroyDart = void Function(int handle);
typedef _MlcEngineChatNative =
    Pointer<Utf8> Function(Int32 handle, Pointer<Utf8> requestJson);
typedef _MlcEngineChatDart = Pointer<Utf8> Function(
  int handle,
  Pointer<Utf8> requestJson,
);
typedef _MlcFreeStringNative = Void Function(Pointer<Utf8> value);
typedef _MlcFreeStringDart = void Function(Pointer<Utf8> value);

class MlcEngine {
  MlcEngine._();
  static final MlcEngine instance = MlcEngine._();

  DynamicLibrary? _library;
  _MlcEngineCreateDart? _engineCreate;
  _MlcEngineDestroyDart? _engineDestroy;
  _MlcEngineChatDart? _engineChat;
  _MlcFreeStringDart? _freeString;
  int? _engineHandle;

  Future<void> initialize({required String modelPath}) async {
    if (_engineHandle != null) return;
    _loadBindingsIfNeeded();
    if (_engineCreate == null) {
      throw Exception('MLC runtime is not available on this platform.');
    }

    final modelPathPointer = modelPath.toNativeUtf8();
    try {
      final handle = _engineCreate!(modelPathPointer);
      if (handle <= 0) {
        throw Exception('Failed to initialize MLC engine.');
      }
      _engineHandle = handle;
    } finally {
      calloc.free(modelPathPointer);
    }
  }

  Future<String> complete({
    required String prompt,
    required Map<String, dynamic> jsonSchema,
  }) async {
    final handle = _engineHandle;
    if (handle == null || _engineChat == null || _freeString == null) {
      throw Exception('MLC engine is not initialized.');
    }

    final request = jsonEncode({
      'messages': [
        {'role': 'system', 'content': prompt},
      ],
      'response_format': {'type': 'json_object'},
      'xgrammar': {'schema': jsonSchema},
    });
    final requestPointer = request.toNativeUtf8();
    try {
      final responsePointer = _engineChat!(handle, requestPointer);
      if (responsePointer == nullptr) {
        throw Exception('MLC engine returned an empty response.');
      }
      try {
        return responsePointer.toDartString();
      } finally {
        _freeString!(responsePointer);
      }
    } finally {
      calloc.free(requestPointer);
    }
  }

  Future<void> release() async {
    if (_engineHandle != null && _engineDestroy != null) {
      _engineDestroy!(_engineHandle!);
    }
    _engineHandle = null;
  }

  void _loadBindingsIfNeeded() {
    if (_library != null) return;
    try {
      _library = _openPlatformLibrary();
      _engineCreate = _library!.lookupFunction<
        _MlcEngineCreateNative,
        _MlcEngineCreateDart
      >('mlc_engine_create');
      _engineDestroy = _library!.lookupFunction<
        _MlcEngineDestroyNative,
        _MlcEngineDestroyDart
      >('mlc_engine_destroy');
      _engineChat = _library!.lookupFunction<
        _MlcEngineChatNative,
        _MlcEngineChatDart
      >('mlc_engine_chat_completion');
      _freeString = _library!.lookupFunction<
        _MlcFreeStringNative,
        _MlcFreeStringDart
      >('mlc_free_string');
    } catch (e) {
      developer.log('Unable to load MLC FFI bindings: $e', name: 'MlcEngine');
      _library = null;
      _engineCreate = null;
      _engineDestroy = null;
      _engineChat = null;
      _freeString = null;
    }
  }

  DynamicLibrary _openPlatformLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libmlc_llm.so');
    }
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError('MLC runtime is only supported on Android/iOS.');
  }
}
