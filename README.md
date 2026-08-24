# AbrKit

AbrKit is a pure Dart reader for Adobe Photoshop brush libraries (`.abr`). It decodes both the documented legacy records and the descriptor-based modern format without Flutter, native code, or a third-party ABR parser.

The package is designed for editors that need more than thumbnails: it exposes sampled and procedural tips, brush settings, embedded texture patterns, group hierarchy, unknown extension data, and the complete Photoshop Action Descriptors.

## Supported data

- Legacy ABR versions 1 and 2, including computed and sampled brushes.
- Modern ABR versions 6, 7, 9, and 10 with subversions 1 and 2.
- `samp` tips at 1, 8, and 16 bits, stored raw or with row-based PackBits compression.
- `desc` brush presets and their complete version 16 Action Descriptors.
- `patt` embedded patterns in every Photoshop color mode, with 1, 8, 16, and 32-bit raw or PackBits channels.
- `phry` brush-group hierarchy entries.
- Computed, sampled, bristle, erodible, custom height-map, and airbrush tips.
- Shape dynamics, scattering, texture, dual brush, color dynamics, transfer, brush pose, and saved tool options.
- Unknown sections, descriptor properties, compression codes, and legacy records preserved for forward compatibility.

Modern ABR is not publicly specified in full. AbrKit therefore keeps the generic descriptor and original bounded payloads alongside typed values so applications do not lose fields that have not yet been given a semantic model.

## Usage

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:abrkit/abrkit.dart';

final Uint8List bytes = await File('brushes.abr').readAsBytes();
final AbrFile library = AbrDecoder.decode(bytes);

for (final AbrBrush brush in library.brushes) {
  print(brush.name);

  switch (brush.shape) {
    case AbrSampledBrushShape shape:
      final AbrSample? sample = library.sampleFor(shape);
      if (sample != null) {
        print('${sample.width} × ${sample.height}');
      }
    case AbrComputedBrushShape shape:
      print('${shape.diameter}px at ${shape.hardness * 100}% hardness');
    case AbrBrushShape():
      print(brush.shape.runtimeType);
  }
}
```

`AbrSample.alpha` contains one normalized 8-bit mask value per pixel in row-major order. For 16-bit sources, `AbrSample.alpha16` also retains every full-precision sample. Bounds retain the original Photoshop-space origin.

## Strict and tolerant decoding

Tolerant decoding is the default. Recoverable extensions are preserved and reported through `AbrFile.warnings`:

```dart
final AbrFile library = AbrDecoder.decode(bytes);
for (final AbrWarning warning in library.warnings) {
  print(warning);
}
```

Strict mode turns every compatibility warning into an `AbrFormatException`:

```dart
final AbrFile library = AbrDecoder.decode(
  bytes,
  options: const AbrDecodeOptions(mode: AbrDecodeMode.strict),
);
```

`AbrDecodeOptions` also bounds file size, section size, decoded bitmap memory, dimensions, collection counts, and Action Descriptor complexity for untrusted input. Set `preserveSectionData` to `false` when the typed models and descriptors are sufficient and retaining complete section payloads would use too much memory.

## Scope

AbrKit reads libraries but does not currently write ABR files or render complete Photoshop brush strokes. A host editor remains responsible for the dab engine, dynamics over time, texture compositing, and tool behavior. The raw descriptors make it possible to add those behaviors incrementally without reparsing the file.

See [docs/ABR.md](docs/ABR.md) for the implemented binary-layout notes and compatibility matrix.

## References

- [Adobe Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)
- [GIMP ABR reader](https://github.com/GNOME/gimp/blob/master/app/core/gimpbrush-load.c)
- [ag-psd ABR reader](https://github.com/Agamnentzar/ag-psd/blob/master/src/abr.ts)
- [Patchy ABR reader](https://github.com/SethRobinson/Patchy/blob/main/src/psd/abr_reader.cpp)

AbrKit is an independent implementation and is not affiliated with or endorsed by Adobe.
