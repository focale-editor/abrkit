import 'dart:io';
import 'dart:typed_data';

import 'package:abrkit/abrkit.dart';

/// Prints a concise structural report for one ABR file.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/inspect_abr.dart <file.abr>');
    exitCode = 64;
    return;
  }
  final File source = File(arguments.single);
  final Uint8List bytes = source.readAsBytesSync();
  final AbrFile file = AbrDecoder.decode(bytes);
  stdout
    ..writeln('ABR ${file.version}.${file.subversion ?? 0} (${file.family.name})')
    ..writeln('${file.brushes.length} brushes, ${file.samples.length} samples, ${file.patterns.length} patterns')
    ..writeln('${file.hierarchy.length} hierarchy entries, ${file.warnings.length} warnings');
  for (final AbrBrush brush in file.brushes) {
    stdout.writeln('- ${brush.name}: ${brush.shape.runtimeType}');
    final AbrBrushSettings? settings = brush.settings;
    if (settings != null) {
      stdout.writeln(
        '  shape=${settings.shapeDynamics != null}, scatter=${settings.scatter != null}, texture=${settings.texture != null}, '
        'dual=${settings.dualBrush != null}, color=${settings.colorDynamics != null}, transfer=${settings.transfer != null}, pose=${settings.pose != null}',
      );
    }
  }
  for (final AbrSample sample in file.samples) {
    stdout.writeln('  sample ${sample.id}: ${sample.width}x${sample.height} ${sample.depth}-bit, ${sample.trailingData.length} trailing bytes');
  }
  for (final AbrWarning warning in file.warnings) {
    stdout.writeln('! $warning');
  }
}
