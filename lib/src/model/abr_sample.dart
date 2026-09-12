import 'dart:typed_data';

/// A rectangular region using Photoshop's top-left-bottom-right convention.
final class AbrBounds {
  /// Vertical coordinate of the first row.
  final int top;

  /// Horizontal coordinate of the first column.
  final int left;

  /// Exclusive vertical coordinate after the last row.
  final int bottom;

  /// Exclusive horizontal coordinate after the last column.
  final int right;

  /// Creates a rectangle from inclusive top/left and exclusive bottom/right edges.
  const AbrBounds({
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
  });

  /// Number of columns in the rectangle.
  int get width => right - left;

  /// Number of rows in the rectangle.
  int get height => bottom - top;

  /// Number of pixels in the rectangle.
  int get pixelCount => width * height;

  /// Whether both dimensions are strictly positive.
  bool get isValid => width > 0 && height > 0;
}

/// Compression marker used by ABR bitmap samples and pattern channels.
enum AbrCompression {
  /// Samples are stored directly in row-major order.
  raw(code: 0),

  /// Rows are compressed independently with PackBits.
  packBits(code: 1),

  /// The marker is not currently defined by the known ABR variants.
  unknown(code: -1);

  /// Numeric marker stored in the file.
  final int code;

  /// Creates a compression value with its on-disk [code].
  const AbrCompression({required this.code});

  /// Resolves a numeric ABR compression [code].
  static AbrCompression fromCode(int code) => switch (code) {
    0 => raw,
    1 => packBits,
    _ => unknown,
  };
}

/// A decoded grayscale brush-tip bitmap from an ABR library.
final class AbrSample {
  /// Stable identifier used by modern sampled-brush descriptors.
  final String id;

  /// Optional human-readable name stored by legacy version 2 files.
  final String? name;

  /// Pixel bounds and source-space origin.
  final AbrBounds bounds;

  /// Source precision, normally 8 or 16 bits per sample.
  final int depth;

  /// Compression marker used by the original payload.
  final AbrCompression compression;

  /// Original numeric compression marker.
  final int compressionCode;

  /// Row-major 8-bit opacity, normalized from the source precision.
  final Uint8List alpha;

  /// Row-major full-precision samples when [depth] is 16.
  final Uint16List? alpha16;

  /// Header bytes whose meaning is not publicly documented.
  final Uint8List metadata;

  /// Bytes following the decoded bitmap inside the bounded sample entry.
  final Uint8List trailingData;

  /// Legacy anti-alias flag, when stored by the source version.
  final bool? antiAliased;

  /// Creates an immutable sampled brush tip.
  AbrSample({
    required this.id,
    required this.bounds,
    required this.depth,
    required this.compression,
    required Uint8List alpha,
    Uint16List? alpha16,
    Uint8List? metadata,
    Uint8List? trailingData,
    int? compressionCode,
    this.name,
    this.antiAliased,
  }) : alpha = Uint8List.fromList(alpha).asUnmodifiableView(),
       alpha16 = alpha16 == null ? null : Uint16List.fromList(alpha16).asUnmodifiableView(),
       compressionCode = compressionCode ?? compression.code,
       metadata = Uint8List.fromList(metadata ?? Uint8List(0)).asUnmodifiableView(),
       trailingData = Uint8List.fromList(trailingData ?? Uint8List(0)).asUnmodifiableView();

  /// Creates one reusable, analytically rasterized square tip.
  ///
  /// Keep the generated sample axis-aligned and express a diamond through a
  /// sampled brush's `45` degree angle. Modern ABR files can then share this
  /// single bitmap between square and diamond presets instead of storing two
  /// separately rasterized tips.
  ///
  /// [sampleSize] controls stored bitmap resolution; the preset's displayed
  /// size remains the sampled brush's diameter.
  ///
  /// [hardness] is the normalized half-width of the fully opaque inner square.
  /// The remaining edge fades linearly. [supersampling] controls how many
  /// subpixels are averaged along each axis.
  factory AbrSample.square({
    required String id,
    required int sampleSize,
    String? name,
    double hardness = 1,
    int depth = 8,
    int supersampling = 4,
    AbrCompression compression = AbrCompression.packBits,
  }) {
    if (sampleSize <= 0) {
      throw RangeError.value(sampleSize, 'sampleSize', 'Must be greater than zero');
    }
    if (!hardness.isFinite || hardness < 0 || hardness > 1) {
      throw RangeError.value(hardness, 'hardness', 'Must be finite and between zero and one');
    }
    if (depth != 8 && depth != 16) {
      throw ArgumentError.value(depth, 'depth', 'Only 8-bit and 16-bit generated samples are supported');
    }
    if (supersampling <= 0 || supersampling > 16) {
      throw RangeError.value(supersampling, 'supersampling', 'Must be between one and sixteen');
    }
    if (compression == AbrCompression.unknown) {
      throw ArgumentError.value(compression, 'compression', 'Generated samples require a known compression');
    }
    final ({Uint8List alpha, Uint16List? alpha16}) raster = _rasterizeSquare(
      sampleSize: sampleSize,
      hardness: hardness,
      depth: depth,
      supersampling: supersampling,
    );
    return AbrSample(
      id: id,
      name: name,
      bounds: AbrBounds(
        top: 0,
        left: 0,
        bottom: sampleSize,
        right: sampleSize,
      ),
      depth: depth,
      compression: compression,
      alpha: raster.alpha,
      alpha16: raster.alpha16,
      antiAliased: supersampling > 1 || hardness < 1,
    );
  }

  /// Width of the decoded opacity bitmap.
  int get width => bounds.width;

  /// Height of the decoded opacity bitmap.
  int get height => bounds.height;

  /// Returns the 8-bit opacity at [x], [y].
  int alphaAt({
    required int x,
    required int y,
  }) {
    RangeError.checkValueInInterval(x, 0, width - 1, 'x');
    RangeError.checkValueInInterval(y, 0, height - 1, 'y');
    return alpha[y * width + x];
  }
}

/// Rasterizes a centered square into normalized 8-bit and optional 16-bit opacity.
({Uint8List alpha, Uint16List? alpha16}) _rasterizeSquare({
  required int sampleSize,
  required double hardness,
  required int depth,
  required int supersampling,
}) {
  final int pixelCount = sampleSize * sampleSize;
  final Uint8List alpha = Uint8List(pixelCount);
  final Uint16List? alpha16 = depth == 16 ? Uint16List(pixelCount) : null;
  final int subpixelCount = supersampling * supersampling;
  final double coordinateScale = 2 / (sampleSize * supersampling);
  for (int y = 0; y < sampleSize; y++) {
    for (int x = 0; x < sampleSize; x++) {
      double opacitySum = 0;
      for (int subpixelY = 0; subpixelY < supersampling; subpixelY++) {
        final double normalizedY = ((y * supersampling + subpixelY + 0.5) * coordinateScale - 1).abs();
        for (int subpixelX = 0; subpixelX < supersampling; subpixelX++) {
          final double normalizedX = ((x * supersampling + subpixelX + 0.5) * coordinateScale - 1).abs();
          final double edgeDistance = normalizedX > normalizedY ? normalizedX : normalizedY;
          opacitySum += _squareOpacity(edgeDistance: edgeDistance, hardness: hardness);
        }
      }
      final double opacity = opacitySum / subpixelCount;
      final int index = y * sampleSize + x;
      if (alpha16 case final Uint16List values) {
        final int value = (opacity * 0xffff).round();
        values[index] = value;
        alpha[index] = value >> 8;
      } else {
        alpha[index] = (opacity * 0xff).round();
      }
    }
  }
  return (alpha: alpha, alpha16: alpha16);
}

/// Returns the opacity at one Chebyshev distance from the square's center.
double _squareOpacity({
  required double edgeDistance,
  required double hardness,
}) {
  if (edgeDistance <= hardness || hardness == 1) {
    return 1;
  }
  if (edgeDistance >= 1) {
    return 0;
  }
  return (1 - edgeDistance) / (1 - hardness);
}
