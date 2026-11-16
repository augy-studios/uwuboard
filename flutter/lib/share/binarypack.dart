// BinaryPack, the format PeerJS sends a data channel's messages in by default (js-binarypack, a
// MessagePack-like format), so the app talks to the site's sharing (js/p2p.js) on another device.
//
//   0x00-0x7f positive fixnum   0xe0-0xff negative fixnum
//   0x80-0x8f fixmap            0x90-0x9f fixarray
//   0xa0-0xaf fixraw (bytes)    0xb0-0xbf fixstr
//   0xc0 null  0xc1 undefined  0xc2 false  0xc3 true  0xca float  0xcb double
//   0xcc-0xcf uint8..uint64     0xd0-0xd3 int8..int64
//   0xd8 str16 0xd9 str32  0xda raw16 0xdb raw32  0xdc array16 0xdd array32  0xde map16 0xdf map32
// Big-endian throughout.
import 'dart:convert';
import 'dart:typed_data';

/// Packs values into BinaryPack bytes and unpacks them again.
class BinaryPack {
  BinaryPack._();

  static Uint8List pack(Object? value) {
    final builder = BytesBuilder(copy: false);
    _pack(builder, value);
    return builder.takeBytes();
  }

  static void _writeUint8(BytesBuilder builder, int value) {
    builder.addByte(value & 0xff);
  }

  static void _writeUint16(BytesBuilder builder, int value) {
    builder.add([(value >> 8) & 0xff, value & 0xff]);
  }

  // Through ByteData rather than shifts, which Dart on the web only keeps 32 signed bits of.
  static void _writeUint32(BytesBuilder builder, int value) {
    final byteData = ByteData(4);
    byteData.setUint32(0, value);
    builder.add(byteData.buffer.asUint8List());
  }

  // By hand, as ByteData's 64-bit calls aren't there in Dart on the web, and the host's clock in
  // every snapshot is over 32 bits. js-binarypack writes them as two 32-bit halves too.
  static void _writeInt64(BytesBuilder builder, int value) {
    final highHalf = (value / 4294967296).floor();
    final lowHalf = value - highHalf * 4294967296;
    if (highHalf < 0) {
      _writeUint32(builder, highHalf + 4294967296);
    } else {
      _writeUint32(builder, highHalf);
    }
    _writeUint32(builder, lowHalf);
  }

  /// Writes one value: a type byte (and its length, for strings, bytes, lists and maps), then
  /// its contents. Lists and maps write each of their items the same way.
  static void _pack(BytesBuilder builder, Object? value) {
    if (value == null) {
      _writeUint8(builder, 0xc0);
      return;
    }
    if (value is bool) {
      if (value) {
        _writeUint8(builder, 0xc3);
      } else {
        _writeUint8(builder, 0xc2);
      }
      return;
    }
    if (value is int) {
      _packInteger(builder, value);
      return;
    }
    if (value is double) {
      if (value == value.truncateToDouble() && value.abs() < 9007199254740992) {
        _packInteger(builder, value.toInt());
        return;
      }
      _writeUint8(builder, 0xcb);
      final byteData = ByteData(8);
      byteData.setFloat64(0, value);
      builder.add(byteData.buffer.asUint8List());
      return;
    }
    if (value is String) {
      final bytes = utf8.encode(value);
      if (bytes.length <= 0x0f) {
        _writeUint8(builder, 0xb0 | bytes.length);
      } else if (bytes.length <= 0xffff) {
        _writeUint8(builder, 0xd8);
        _writeUint16(builder, bytes.length);
      } else {
        _writeUint8(builder, 0xd9);
        _writeUint32(builder, bytes.length);
      }
      builder.add(bytes);
      return;
    }
    if (value is Uint8List) {
      if (value.length <= 0x0f) {
        _writeUint8(builder, 0xa0 | value.length);
      } else if (value.length <= 0xffff) {
        _writeUint8(builder, 0xda);
        _writeUint16(builder, value.length);
      } else {
        _writeUint8(builder, 0xdb);
        _writeUint32(builder, value.length);
      }
      builder.add(value);
      return;
    }
    if (value is List) {
      if (value.length <= 0x0f) {
        _writeUint8(builder, 0x90 | value.length);
      } else if (value.length <= 0xffff) {
        _writeUint8(builder, 0xdc);
        _writeUint16(builder, value.length);
      } else {
        _writeUint8(builder, 0xdd);
        _writeUint32(builder, value.length);
      }
      for (final item in value) {
        _pack(builder, item);
      }
      return;
    }
    if (value is Map) {
      final count = value.length;
      if (count <= 0x0f) {
        _writeUint8(builder, 0x80 | count);
      } else if (count <= 0xffff) {
        _writeUint8(builder, 0xde);
        _writeUint16(builder, count);
      } else {
        _writeUint8(builder, 0xdf);
        _writeUint32(builder, count);
      }
      value.forEach((key, item) {
        if (key is String) {
          _pack(builder, key);
        } else {
          _pack(builder, '$key');
        }
        _pack(builder, item);
      });
      return;
    }
    // Anything else as its words, as JSON would have it.
    _pack(builder, '$value');
  }

  // In js-binarypack's order, so the same number is packed the same way.
  static void _packInteger(BytesBuilder builder, int number) {
    if (-0x20 <= number && number <= 0x7f) {
      _writeUint8(builder, number);
      return;
    }
    if (0 <= number && number <= 0xff) {
      _writeUint8(builder, 0xcc);
      _writeUint8(builder, number);
      return;
    }
    if (-0x80 <= number && number <= 0x7f) {
      _writeUint8(builder, 0xd0);
      _writeUint8(builder, number);
      return;
    }
    if (0 <= number && number <= 0xffff) {
      _writeUint8(builder, 0xcd);
      _writeUint16(builder, number);
      return;
    }
    if (-0x8000 <= number && number <= 0x7fff) {
      _writeUint8(builder, 0xd1);
      _writeUint16(builder, number);
      return;
    }
    if (0 <= number && number <= 0xffffffff) {
      _writeUint8(builder, 0xce);
      _writeUint32(builder, number);
      return;
    }
    if (-0x80000000 <= number && number <= 0x7fffffff) {
      _writeUint8(builder, 0xd2);
      _writeUint32(builder, number);
      return;
    }
    _writeUint8(builder, 0xd3);
    _writeInt64(builder, number);
  }

  static Object? unpack(Uint8List bytes) {
    return _Reader(bytes).value();
  }
}

/// Reads values back out of BinaryPack bytes, front to back.
class _Reader {
  _Reader(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;

  /// Where the next byte to read is.
  int position = 0;

  int _readUint8() {
    final index = position;
    position = position + 1;
    return bytes[index];
  }

  int _readUint16() {
    final number = data.getUint16(position);
    position = position + 2;
    return number;
  }

  int _readUint32() {
    final number = data.getUint32(position);
    position = position + 4;
    return number;
  }

  String _readString(int length) {
    final text = utf8.decode(bytes.sublist(position, position + length), allowMalformed: true);
    position = position + length;
    return text;
  }

  Uint8List _readBytes(int length) {
    final copy = Uint8List.fromList(bytes.sublist(position, position + length));
    position = position + length;
    return copy;
  }

  List<Object?> _readArray(int length) {
    return [for (var index = 0; index < length; index = index + 1) value()];
  }

  Map<String, Object?> _readMap(int length) {
    final map = <String, Object?>{};
    for (var index = 0; index < length; index = index + 1) {
      final key = value();
      map['$key'] = value();
    }
    return map;
  }

  /// Reads the next value: its type byte says what it is and, for the small kinds, its size.
  Object? value() {
    final typeByte = _readUint8();
    if (typeByte < 0x80) {
      return typeByte;
    }
    if ((typeByte ^ 0xe0) < 0x20) {
      return (typeByte ^ 0xe0) - 0x20;
    }
    if ((typeByte ^ 0xa0) <= 0x0f) {
      return _readBytes(typeByte ^ 0xa0);
    }
    if ((typeByte ^ 0xb0) <= 0x0f) {
      return _readString(typeByte ^ 0xb0);
    }
    if ((typeByte ^ 0x90) <= 0x0f) {
      return _readArray(typeByte ^ 0x90);
    }
    if ((typeByte ^ 0x80) <= 0x0f) {
      return _readMap(typeByte ^ 0x80);
    }
    switch (typeByte) {
      case 0xc0:
      case 0xc1:
        return null;
      case 0xc2:
        return false;
      case 0xc3:
        return true;
      case 0xca:
        final number = data.getFloat32(position);
        position = position + 4;
        return number;
      case 0xcb:
        final number = data.getFloat64(position);
        position = position + 8;
        return number;
      case 0xcc:
        return _readUint8();
      case 0xcd:
        return _readUint16();
      case 0xce:
        return _readUint32();
      case 0xcf:
        final highHalf = _readUint32();
        final lowHalf = _readUint32();
        return highHalf * 4294967296 + lowHalf;
      case 0xd0:
        final index = position;
        position = position + 1;
        return data.getInt8(index);
      case 0xd1:
        final number = data.getInt16(position);
        position = position + 2;
        return number;
      case 0xd2:
        final number = data.getInt32(position);
        position = position + 4;
        return number;
      case 0xd3:
        final highHalf = data.getInt32(position);
        final lowHalf = data.getUint32(position + 4);
        position = position + 8;
        return highHalf * 4294967296 + lowHalf;
      case 0xd8:
        return _readString(_readUint16());
      case 0xd9:
        return _readString(_readUint32());
      case 0xda:
        return _readBytes(_readUint16());
      case 0xdb:
        return _readBytes(_readUint32());
      case 0xdc:
        return _readArray(_readUint16());
      case 0xdd:
        return _readArray(_readUint32());
      case 0xde:
        return _readMap(_readUint16());
      case 0xdf:
        return _readMap(_readUint32());
    }
    return null;
  }
}
