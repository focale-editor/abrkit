import 'dart:io';
import 'dart:typed_data';

import 'package:abrkit/abrkit.dart';

/// Prints the brush presets and their available tip dimensions from one ABR library.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run example/main.dart <library.abr>');
    exitCode = 64;
    return;
  }

  final Uint8List bytes = await File(arguments.single).readAsBytes();
  final AbrFile library = AbrDecoder.decode(
    bytes,
    options: const AbrDecodeOptions(preserveSectionData: false),
  );
  for (final AbrBrush brush in library.brushes) {
    final String details = switch (brush.shape) {
      final AbrSampledBrushShape shape => switch (library.sampleFor(shape)) {
        final AbrSample sample => '${sample.width} × ${sample.height} (${sample.id})',
        null => 'sample ${shape.sampleId} is not embedded',
      },
      final AbrComputedBrushShape shape => '${shape.diameter}px at ${shape.hardness * 100}% hardness',
      AbrBrushShape() => brush.shape.runtimeType.toString(),
    };
    stdout.writeln('${brush.name}: $details');
  }
  library.warnings.forEach(stderr.writeln);
}
