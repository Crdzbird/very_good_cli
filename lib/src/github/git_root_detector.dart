import 'package:path/path.dart' as path;
import 'package:universal_io/io.dart';

/// {@template git_root_detector}
/// Locates the root of the git repository containing a directory.
/// {@endtemplate}
class GitRootDetector {
  /// {@macro git_root_detector}
  const GitRootDetector();

  /// Returns the root [Directory] of the git repository containing [from],
  /// or `null` when [from] is not inside a git repository.
  ///
  /// Walks up the file system until a `.git` entity is found. The entity may
  /// be a directory (regular repositories) or a file (worktrees and
  /// submodules).
  Directory? detect(Directory from) {
    var directory = Directory(path.normalize(from.absolute.path));

    while (true) {
      final gitPath = path.join(directory.path, '.git');
      if (FileSystemEntity.typeSync(gitPath) != FileSystemEntityType.notFound) {
        return directory;
      }

      final parent = directory.parent;
      if (parent.path == directory.path) return null;
      directory = parent;
    }
  }
}
