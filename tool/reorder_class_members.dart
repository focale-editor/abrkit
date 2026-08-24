import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Reorders Dart type declarations as fields, constructors, then methods.
void main(List<String> arguments) {
  final List<File> files = _dartFiles(arguments.isEmpty ? <String>['lib'] : arguments);
  for (final File file in files) {
    final String source = file.readAsStringSync();
    final CompilationUnit unit = parseString(content: source, path: file.path).unit;
    final List<_SourceEdit> edits = <_SourceEdit>[];
    for (final CompilationUnitMember declaration in unit.declarations) {
      final NodeList<ClassMember>? members = switch (declaration) {
        ClassDeclaration(:final ClassBody body) => body.members,
        EnumDeclaration(:final EnumBody body) => body.members,
        MixinDeclaration(:final ClassBody body) => body.members,
        ExtensionDeclaration(:final ClassBody body) => body.members,
        _ => null,
      };
      if (members != null) {
        final _SourceEdit? edit = _reorderEdit(source, members);
        if (edit != null) {
          edits.add(edit);
        }
      }
    }
    if (edits.isEmpty) {
      continue;
    }
    String updated = source;
    edits.sort((left, right) => right.offset.compareTo(left.offset));
    for (final _SourceEdit edit in edits) {
      updated = updated.replaceRange(edit.offset, edit.offset + edit.length, edit.replacement);
    }
    file.writeAsStringSync(updated);
  }
}

/// A source replacement produced for one type declaration.
final class _SourceEdit {
  /// Starting source offset.
  final int offset;

  /// Number of source characters replaced.
  final int length;

  /// Reordered member source.
  final String replacement;

  /// Creates one source replacement.
  const _SourceEdit({
    required this.offset,
    required this.length,
    required this.replacement,
  });
}

/// Returns every Dart file beneath the requested files or directories.
List<File> _dartFiles(List<String> paths) {
  final List<File> files = <File>[];
  for (final String path in paths) {
    final FileSystemEntityType type = FileSystemEntity.typeSync(path);
    switch (type) {
      case FileSystemEntityType.file:
        if (path.endsWith('.dart')) {
          files.add(File(path));
        }
      case FileSystemEntityType.directory:
        files.addAll(
          Directory(path).listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart')),
        );
      case FileSystemEntityType.link:
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        break;
    }
  }
  return files;
}

/// Creates a stable grouped replacement when [members] are out of order.
_SourceEdit? _reorderEdit(String source, NodeList<ClassMember> members) {
  if (members.length < 2) {
    return null;
  }
  final List<ClassMember> ordered = List<ClassMember>.of(members)
    ..sort((left, right) {
      final int category = _memberCategory(left).compareTo(_memberCategory(right));
      return category == 0 ? members.indexOf(left).compareTo(members.indexOf(right)) : category;
    });
  if (_sameOrder(members, ordered)) {
    return null;
  }
  final int start = _memberStart(members.first);
  final int end = members.last.end;
  final int lineStart = source.lastIndexOf('\n', start - 1) + 1;
  final String indentation = source.substring(lineStart, start);
  final List<String> snippets = <String>[
    for (final ClassMember member in ordered) source.substring(_memberStart(member), member.end),
  ];
  return _SourceEdit(
    offset: start,
    length: end - start,
    replacement: snippets.join('\n\n$indentation'),
  );
}

/// Returns zero for fields, one for constructors, and two for methods.
int _memberCategory(ClassMember member) => switch (member) {
  FieldDeclaration() => 0,
  ConstructorDeclaration() => 1,
  _ => 2,
};

/// Includes a member's documentation and annotations in its source span.
int _memberStart(ClassMember member) {
  final int documentationOffset = member.documentationComment?.offset ?? member.offset;
  final int metadataOffset = member.metadata.isEmpty ? member.offset : member.metadata.first.offset;
  return documentationOffset < metadataOffset ? documentationOffset : metadataOffset;
}

/// Reports whether two member lists contain the identical node order.
bool _sameOrder(List<ClassMember> left, List<ClassMember> right) {
  for (int index = 0; index < left.length; index++) {
    if (!identical(left[index], right[index])) {
      return false;
    }
  }
  return true;
}
