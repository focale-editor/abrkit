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
