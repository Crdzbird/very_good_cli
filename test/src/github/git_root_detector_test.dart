import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:very_good_cli/src/github/github.dart';

void main() {
  group('GitRootDetector', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('vg_git_root_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('can be instantiated at runtime', () {
      const create = GitRootDetector.new;
      expect(create(), isA<GitRootDetector>());
    });

    test('returns null when not inside a git repository', () {
      final nested = Directory(path.join(tempDir.path, 'a', 'b'))
        ..createSync(recursive: true);

      expect(const GitRootDetector().detect(nested), isNull);
    });

    test('detects a repository root with a .git directory', () {
      Directory(path.join(tempDir.path, '.git')).createSync();
      final nested = Directory(path.join(tempDir.path, 'packages', 'pkg'))
        ..createSync(recursive: true);

      final root = const GitRootDetector().detect(nested);

      expect(
        root?.path,
        equals(path.normalize(tempDir.absolute.path)),
      );
    });

    test('detects a repository root with a .git file (worktree)', () {
      File(
        path.join(tempDir.path, '.git'),
      ).writeAsStringSync('gitdir: /elsewhere/.git/worktrees/x\n');
      final nested = Directory(path.join(tempDir.path, 'apps', 'app'))
        ..createSync(recursive: true);

      final root = const GitRootDetector().detect(nested);

      expect(
        root?.path,
        equals(path.normalize(tempDir.absolute.path)),
      );
    });

    test('returns the directory itself when it is the repository root', () {
      Directory(path.join(tempDir.path, '.git')).createSync();

      final root = const GitRootDetector().detect(tempDir);

      expect(
        root?.path,
        equals(path.normalize(tempDir.absolute.path)),
      );
    });
  });
}
