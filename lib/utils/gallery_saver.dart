import 'dart:typed_data';
import 'package:gal/gal.dart';

/// 保存图片到系统相册（先申请权限）。
Future<void> saveImageBytesToGallery(
  Uint8List bytes, {
  String name = 'ai_image',
}) async {
  final hasAccess = await Gal.hasAccess();
  if (!hasAccess) {
    final granted = await Gal.requestAccess();
    if (!granted) {
      throw Exception('没有相册权限，请在系统设置中允许');
    }
  }
  await Gal.putImageBytes(bytes, name: name);
}
