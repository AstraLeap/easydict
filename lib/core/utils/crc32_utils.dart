import 'dart:io';
import 'dart:typed_data';

/// CRC32 计算工具类
///
/// 用于计算文件或字节数组的 CRC32 校验值
class Crc32Utils {
  /// CRC32 查找表
  static final List<int> _crc32Table = _generateCrc32Table();

  /// 生成 CRC32 查找表
  static List<int> _generateCrc32Table() {
    const polynomial = 0xEDB88320;
    final table = List<int>.filled(256, 0);

    for (int i = 0; i < 256; i++) {
      int crc = i;
      for (int j = 0; j < 8; j++) {
        if (crc & 1 != 0) {
          crc = (crc >> 1) ^ polynomial;
        } else {
          crc = crc >> 1;
        }
      }
      table[i] = crc;
    }

    return table;
  }

  /// 计算字节数组的 CRC32 值
  ///
  /// [bytes] - 要计算的字节数组
  /// 返回 CRC32 值的十六进制字符串（小写）
  static String calculateBytesCrc32(Uint8List bytes) {
    int crc = 0xFFFFFFFF;

    for (final byte in bytes) {
      final index = (crc ^ byte) & 0xFF;
      crc = (crc >> 8) ^ _crc32Table[index];
    }

    crc = crc ^ 0xFFFFFFFF;
    return crc.toUnsigned(32).toRadixString(16).padLeft(8, '0');
  }

  /// 计算文件的 CRC32 值
  ///
  /// [file] - 要计算的文件
  /// 返回 CRC32 值的十六进制字符串（小写）
  ///
  /// 使用流式读取，支持大文件
  static Future<String> calculateFileCrc32(File file) async {
    int crc = 0xFFFFFFFF;

    final stream = file.openRead();
    await for (final chunk in stream) {
      for (final byte in chunk) {
        final index = (crc ^ byte) & 0xFF;
        crc = (crc >> 8) ^ _crc32Table[index];
      }
    }

    crc = crc ^ 0xFFFFFFFF;
    return crc.toUnsigned(32).toRadixString(16).padLeft(8, '0');
  }

  /// 比较两个 CRC32 值是否相等（忽略大小写）
  ///
  /// [crc1] - 第一个 CRC32 值
  /// [crc2] - 第二个 CRC32 值
  /// 返回是否相等
  static bool compareCrc32(String crc1, String crc2) {
    return crc1.toLowerCase() == crc2.toLowerCase();
  }
}
