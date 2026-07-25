/// 文件字节读取工具（跨端兼容）。
///
/// 用于在发布时读取构建产物的字节：
/// - 非 Web 平台：通过 dart:io 读取文件系统。
/// - Web 平台：永远返回 null（Web 平台构建产物以 bytes 内存形式存在，
///   调用方在传入前已通过 `BuildArtifact.bytes` 直接获取）。
///
/// 通过 conditional import 实现：编译期根据平台选择具体实现，
/// Web 平台不会引入 dart:io（否则编译失败）。
library;

import 'dart:typed_data';

import 'artifact_bytes_stub.dart'
    if (dart.library.io) 'artifact_bytes_io.dart' as impl;

/// 读取 [path] 对应文件的字节。
///
/// 非 Web 平台：成功返回字节，文件不存在或读取失败返回 null。
/// Web 平台：永远返回 null（Web 平台不走此路径）。
Future<Uint8List?> readArtifactFileBytes(String path) =>
    impl.readArtifactFileBytesImpl(path);
