/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:ffi';

import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/src/player/native/core/execmem_restriction.dart';
import 'package:media_kit/src/player/native/core/initializer_isolate.dart';
import 'package:media_kit/src/player/native/core/initializer_native_callable.dart';
import 'package:media_kit/src/player/native/core/initializer_native_event_loop.dart';

/// {@template initializer}
///
/// Initializer
/// -----------
/// Initializes [Pointer<mpv_handle>] & notifies about events through the supplied callback.
///
/// {@endtemplate}
class Initializer {
  /// Singleton instance.
  static Initializer? _instance;

  /// {@macro initializer}
  Initializer._(this.mpv);

  /// {@macro initializer}
  factory Initializer(generated.MPV mpv) {
    _instance ??= Initializer._(mpv);
    return _instance!;
  }

  /// Generated libmpv C API bindings.
  final generated.MPV mpv;

  /// Tracks which backend created each [Pointer<mpv_handle>].
  final _useNativeEventLoop = <int, bool>{};

  /// Creates [Pointer<mpv_handle>].
  Future<Pointer<generated.mpv_handle>> create(
    Future<void> Function(Pointer<generated.mpv_event>) callback, {
    Map<String, String> options = const {},
  }) async {
    try {
      final handle = InitializerNativeEventLoop.create(mpv, callback, options);
      _useNativeEventLoop[handle.address] = true;
      return handle;
    } catch (e, s) {
      Zone.current.handleUncaughtError(e, s);
      if (!isExecmemRestricted) {
        final handle = await InitializerNativeCallable(
          mpv,
        ).create(callback, options: options);
        _useNativeEventLoop[handle.address] = false;
        return handle;
      } else {
        final handle = await InitializerIsolate().create(
          callback,
          options: options,
        );
        _useNativeEventLoop[handle.address] = false;
        return handle;
      }
    }
  }

  /// Disposes [Pointer<mpv_handle>].
  void dispose(Pointer<generated.mpv_handle> ctx) {
    final useNative = _useNativeEventLoop.remove(ctx.address) ?? false;
    if (useNative) {
      try {
        InitializerNativeEventLoop.dispose(ctx);
      } catch (_) {
        InitializerIsolate().dispose(mpv, ctx);
      }
    } else if (!isExecmemRestricted) {
      InitializerNativeCallable(mpv).dispose(ctx);
    } else {
      InitializerIsolate().dispose(mpv, ctx);
    }
  }
}
