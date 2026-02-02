import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final inputPath = args.isNotEmpty ? args.first : 'appIcon.png';
  final outputPath = args.length > 1 ? args[1] : 'appIcon_padded.png';
  const scale = 0.7; // shrink content to 90%

  final bytes = File(inputPath).readAsBytesSync();
  final original = img.decodeImage(bytes);
  if (original == null) {
    stderr.writeln('Failed to decode $inputPath');
    exit(1);
  }

  final nw = (original.width * scale).round();
  final nh = (original.height * scale).round();
  final resized = img.copyResize(original, width: nw, height: nh, interpolation: img.Interpolation.cubic);
  final canvas = img.Image(width: original.width, height: original.height, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  final ox = ((original.width - nw) / 2).round();
  final oy = ((original.height - nh) / 2).round();
  img.compositeImage(canvas, resized, dstX: ox, dstY: oy);

  File(outputPath).writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('Wrote $outputPath (padded) from $inputPath');
}
