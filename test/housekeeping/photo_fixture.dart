import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

Uint8List photoBytes() => Uint8List.fromList(
  img.encodeJpg(
    img.fill(
      img.Image(width: 16, height: 12),
      color: img.ColorRgb8(30, 100, 80),
    ),
    quality: 70,
  ),
);
String photoBase64() => base64Encode(photoBytes());
