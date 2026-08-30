import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Flutter port of Web `sticker-frame.js` — paper-collage (小红书贴纸) + plain.
class StickerFrameOptions {
  final String preset;
  final double padding;
  final Color bgColor;
  final bool glassBg;
  final double glassBlur;
  final double glassFrost;
  final double borderWidth;
  final Color borderColor;
  final double borderRadius;
  final double shadowOffset;
  final double shadowAlpha;
  final double tiltDeg;
  final bool tape;
  final bool plain;
  final int? maxContentWidth;

  const StickerFrameOptions({
    this.preset = 'paper-collage',
    this.padding = 32,
    this.bgColor = const Color(0xFFF6EDDA),
    this.glassBg = true,
    this.glassBlur = 36,
    this.glassFrost = 0.14,
    this.borderWidth = 3,
    this.borderColor = const Color(0xFF26221C),
    this.borderRadius = 14,
    this.shadowOffset = 5,
    this.shadowAlpha = 0.9,
    this.tiltDeg = -1.2,
    this.tape = true,
    this.plain = false,
    this.maxContentWidth,
  });

  const StickerFrameOptions.none({this.maxContentWidth})
      : preset = 'none',
        padding = 0,
        bgColor = const Color(0xFF000000),
        glassBg = false,
        glassBlur = 0,
        glassFrost = 0,
        borderWidth = 0,
        borderColor = const Color(0x00000000),
        borderRadius = 0,
        shadowOffset = 0,
        shadowAlpha = 0,
        tiltDeg = 0,
        tape = false,
        plain = true;

  const StickerFrameOptions.paperCollage({this.maxContentWidth})
      : preset = 'paper-collage',
        padding = 32,
        bgColor = const Color(0xFFF6EDDA),
        glassBg = true,
        glassBlur = 36,
        glassFrost = 0.14,
        borderWidth = 3,
        borderColor = const Color(0xFF26221C),
        borderRadius = 14,
        shadowOffset = 5,
        shadowAlpha = 0.9,
        tiltDeg = -1.2,
        tape = true,
        plain = false;
}

Future<ui.Image> decodeImageBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

Future<Uint8List> imageToPngBytes(ui.Image image) async {
  final bd = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) throw StateError('PNG encode failed');
  return bd.buffer.asUint8List();
}

/// Render source image bytes → PNG bytes (plain or sticker frame).
Future<Uint8List> renderStickerPng(
  Uint8List sourceBytes, {
  StickerFrameOptions options = const StickerFrameOptions.paperCollage(),
}) async {
  final src = await decodeImageBytes(sourceBytes);
  try {
    final painted = await _paintSticker(src, options);
    try {
      return await imageToPngBytes(painted);
    } finally {
      painted.dispose();
    }
  } finally {
    src.dispose();
  }
}

Future<ui.Image> _paintSticker(ui.Image src, StickerFrameOptions opts) async {
  if (opts.plain || opts.preset == 'none') {
    return _paintPlain(src, opts.maxContentWidth);
  }

  const refW = 390.0;
  final imgW = src.width.toDouble();
  final imgH = src.height.toDouble();
  final padBase = opts.padding;
  final borderBase = opts.borderWidth;

  double drawW = imgW;
  double drawH = imgH;
  final maxW = opts.maxContentWidth;
  if (maxW != null && maxW > 0 && imgW > maxW) {
    final s = maxW / imgW;
    drawW = imgW * s;
    drawH = imgH * s;
  }

  final uiScale = drawW / refW;
  final padding = padBase * uiScale;
  final borderWidth = math.max(1.0, borderBase * uiScale);
  final radius = opts.borderRadius * uiScale;
  final shadow = opts.shadowOffset * uiScale;

  final cardW = drawW + borderWidth * 2 + padding * 2;
  final cardH = drawH + borderWidth * 2 + padding * 2;
  // room for tilt + shadow
  final canvasW = (cardW + shadow * 2 + 24 * uiScale).ceilToDouble();
  final canvasH = (cardH + shadow * 2 + 24 * uiScale).ceilToDouble();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final origin = Offset((canvasW - cardW) / 2, (canvasH - cardH) / 2);

  // Outer soft paper background
  canvas.drawRect(
    Rect.fromLTWH(0, 0, canvasW, canvasH),
    Paint()..color = opts.bgColor,
  );

  canvas.save();
  canvas.translate(canvasW / 2, canvasH / 2);
  canvas.rotate(opts.tiltDeg * math.pi / 180);
  canvas.translate(-canvasW / 2, -canvasH / 2);

  final cardRect = origin & Size(cardW, cardH);

  // Glass / frosted bg clipped to card
  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(cardRect, Radius.circular(radius + 4)));
  if (opts.glassBg) {
    await _drawBlurredCover(
      canvas,
      src,
      cardRect,
      blurSigma: math.min(28, opts.glassBlur * (uiScale.clamp(0.4, 1.2))),
    );
    canvas.drawRect(
      cardRect,
      Paint()..color = Colors.white.withValues(alpha: opts.glassFrost),
    );
  } else {
    canvas.drawRect(cardRect, Paint()..color = opts.bgColor);
  }
  canvas.restore();

  // Tape strips
  if (opts.tape) {
    final ts = uiScale;
    _drawTape(
      canvas,
      Rect.fromLTWH(
        origin.dx + padding + 8 * ts,
        origin.dy + padding - 6 * ts,
        52 * ts,
        16 * ts,
      ),
      const Color(0xFF7EB8E8),
    );
    _drawTape(
      canvas,
      Rect.fromLTWH(
        origin.dx + cardW - padding - 60 * ts,
        origin.dy + padding - 6 * ts,
        52 * ts,
        16 * ts,
      ),
      const Color(0xFFF2D4A7),
    );
  }

  final imgRect = Rect.fromLTWH(
    origin.dx + padding,
    origin.dy + padding,
    drawW,
    drawH,
  );

  // Hard sticker shadow
  if (opts.shadowAlpha > 0 && shadow > 0) {
    final shadowRect = imgRect.translate(shadow, shadow);
    canvas.drawRRect(
      RRect.fromRectAndRadius(shadowRect, Radius.circular(radius)),
      Paint()..color = Colors.black.withValues(alpha: opts.shadowAlpha),
    );
  }

  // Photo
  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(imgRect, Radius.circular(radius)));
  paintImage(
    canvas: canvas,
    rect: imgRect,
    image: src,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.high,
  );
  canvas.restore();

  // Border
  if (borderWidth > 0) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(imgRect, Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..color = opts.borderColor,
    );
  }

  canvas.restore(); // tilt

  final picture = recorder.endRecording();
  return picture.toImage(canvasW.ceil(), canvasH.ceil());
}

Future<ui.Image> _paintPlain(ui.Image src, int? maxContentWidth) async {
  var w = src.width;
  var h = src.height;
  if (maxContentWidth != null && maxContentWidth > 0 && w > maxContentWidth) {
    final s = maxContentWidth / w;
    w = (w * s).round();
    h = (h * s).round();
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paintImage(
    canvas: canvas,
    rect: Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    image: src,
    fit: BoxFit.fill,
    filterQuality: FilterQuality.high,
  );
  final picture = recorder.endRecording();
  return picture.toImage(w, h);
}

Future<void> _drawBlurredCover(
  Canvas canvas,
  ui.Image src,
  Rect dest, {
  required double blurSigma,
}) async {
  // Downscale then blur for GPU safety (mirrors Web sticker-frame.js)
  final maxSide = 480.0;
  final scale = math.min(1.0, maxSide / math.max(dest.width, dest.height));
  final offW = math.max(1, (dest.width * scale).ceil());
  final offH = math.max(1, (dest.height * scale).ceil());

  final offRec = ui.PictureRecorder();
  final offCanvas = Canvas(offRec);
  paintImage(
    canvas: offCanvas,
    rect: Rect.fromLTWH(0, 0, offW.toDouble(), offH.toDouble()),
    image: src,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
  );
  final offPic = offRec.endRecording();
  final offImg = await offPic.toImage(offW, offH);

  final paint = Paint()
    ..imageFilter = ui.ImageFilter.blur(sigmaX: blurSigma * scale, sigmaY: blurSigma * scale);
  canvas.saveLayer(dest, paint);
  canvas.drawImageRect(
    offImg,
    Rect.fromLTWH(0, 0, offW.toDouble(), offH.toDouble()),
    dest,
    Paint()..filterQuality = FilterQuality.medium,
  );
  canvas.restore();
  offImg.dispose();
}

void _drawTape(Canvas canvas, Rect rect, Color color) {
  canvas.save();
  canvas.translate(rect.center.dx, rect.center.dy);
  canvas.rotate(-0.18);
  canvas.translate(-rect.width / 2, -rect.height / 2);
  final r = RRect.fromRectAndRadius(
    Rect.fromLTWH(0, 0, rect.width, rect.height),
    const Radius.circular(3),
  );
  canvas.drawRRect(r, Paint()..color = color.withValues(alpha: 0.85));
  canvas.drawRRect(
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black.withValues(alpha: 0.15),
  );
  canvas.restore();
}
