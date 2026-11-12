import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pointycastle/export.dart';

import 'app_exception.dart';

class EvidencePhoto {
  static const maxBytes = 600 * 1024;
  static const maxInputBytes = 10 * 1024 * 1024;
  static Future<Uint8List> prepare(Uint8List bytes) => Isolate.run(() {
    if (bytes.isEmpty || bytes.length > maxInputBytes) _fail();
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.width * info.height > 20000000) _fail();
    final source = decoder!.decodeFrame(0);
    if (source == null) _fail();
    final oriented = img.bakeOrientation(source);
    final resized = img.copyResize(
      oriented,
      width: oriented.width >= oriented.height ? 1280 : null,
      height: oriented.height > oriented.width ? 1280 : null,
      maintainAspect: true,
    );
    // Re-encoding strips the source file's EXIF metadata, including location.
    final clean = img.Image.from(resized)..exif.clear();
    final result = Uint8List.fromList(img.encodeJpg(clean, quality: 70));
    if (result.length > maxBytes) _fail();
    return result;
  });
  static Uint8List validate(String encoded) {
    if (encoded.length > maxBytes * 1.4) _fail();
    Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } catch (_) {
      _fail();
    }
    if (bytes.isEmpty || bytes.length > maxBytes) _fail();
    final decoder = img.JpegDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null ||
        info.width > 1280 ||
        info.height > 1280 ||
        decoder.decodeFrame(0) == null) {
      _fail();
    }
    return bytes;
  }

  static String id(Uint8List bytes) =>
      base64UrlEncode(SHA256Digest().process(bytes));
  static Never _fail() => throw const AppServiceException(
    'Photo invalide ou trop volumineuse. Choisissez une autre image (10 Mo maximum).',
  );
}
