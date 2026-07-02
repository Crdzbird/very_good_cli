import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:very_good_cli/src/github/github.dart';
import 'package:yaml/yaml.dart';

const _dependabot = '''
version: 2
enable-beta-ecosystems: true
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "daily"
  - package-ecosystem: "pub"
    directory: "/"
    schedule:
      interval: "daily"
''';

const _cspell = r'''
{
  "version": "0.2",
  "$schema": "https://raw.githubusercontent.com/streetsidesoftware/cspell/main/cspell.schema.json",
  "dictionaries": ["vgv_allowed", "vgv_forbidden"],
  "dictionaryDefinitions": [
    {
      "name": "vgv_allowed",
      "path": "https://raw.githubusercontent.com/verygoodopensource/very_good_dictionaries/main/allowed.txt",
      "description": "Allowed VGV Spellings"
    },
    {
      "name": "vgv_forbidden",
      "path": "https://raw.githubusercontent.com/verygoodopensource/very_good_dictionaries/main/forbidden.txt",
      "description": "Forbidden VGV Spellings"
    }
  ],
  "useGitignore": true,
  "words": [
    "my_pkg"
  ]
}
''';

const _mainWorkflow = r'''
name: ci

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

jobs:
  semantic_pull_request:
    uses: VeryGoodOpenSource/very_good_workflows/.github/workflows/semantic_pull_request.yml@v1

  spell-check:
    uses: VeryGoodOpenSource/very_good_workflows/.github/workflows/spell_check.yml@v1
    with:
      includes: "**/*.md"
      modified_files_only: false

  build:
    uses: VeryGoodOpenSource/very_good_workflows/.github/workflows/dart_package.yml@v1
    with:
      dart_sdk: "3.12.0"
''';

const _licenseCheckWorkflow = r'''
name: license_check

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

on:
  pull_request:
    branches:
      - main
    paths:
      - "pubspec.yaml"
      - ".github/workflows/license_check.yaml"

jobs:
  license_check:
    uses: VeryGoodOpenSource/very_good_workflows/.github/workflows/license_check.yml@v1
    with:
      allowed: "MIT,BSD-3-Clause,BSD-2-Clause,Apache-2.0"
''';

void main() {
  group('GithubIntegrator', () {
    late Directory root;
    late Directory package;

    setUp(() {
      root = Directory.systemTemp.createTempSync('vg_github_');
      package = Directory(path.join(root.path, 'packages', 'my_pkg'))
        ..createSync(recursive: true);
    });

    tearDown(() => root.deleteSync(recursive: true));

    void writeSource(String relative, String content) {
      File(path.join(package.path, '.github', relative))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    void writeRoot(String relative, String content) {
      File(path.join(root.path, '.github', relative))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    String readRoot(String relative) =>
        File(path.join(root.path, '.github', relative)).readAsStringSync();

    bool rootHas(String relative) =>
        File(path.join(root.path, '.github', relative)).existsSync();

    GithubIntegrationSummary integrate() => const GithubIntegrator().integrate(
      packageDirectory: package,
      repositoryRoot: root,
      projectName: 'my_pkg',
    );

    test('can be instantiated at runtime', () {
      const create = GithubIntegrator.new;
      expect(create(), isA<GithubIntegrator>());
    });

    test('returns an empty summary when the package has no .github', () {
      final summary = integrate();

      expect(summary.isEmpty, isTrue);
    });

    group('with no existing root .github', () {
      setUp(() {
        writeSource('dependabot.yaml', _dependabot);
        writeSource('cspell.json', _cspell);
        writeSource('PULL_REQUEST_TEMPLATE.md', '# PR template\n');
        writeSource('ISSUE_TEMPLATE/config.yml', 'blank_issues_enabled: false');
        writeSource('ISSUE_TEMPLATE/bug_report.md', '# Bug\n');
        writeSource('workflows/main.yaml', _mainWorkflow);
        writeSource('workflows/license_check.yaml', _licenseCheckWorkflow);
      });

      test('relocates every file and removes the package .github', () {
        final summary = integrate();

        expect(
          summary.moved,
          containsAll([
            '.github/dependabot.yaml',
            '.github/cspell.json',
            '.github/PULL_REQUEST_TEMPLATE.md',
            '.github/ISSUE_TEMPLATE/config.yml',
            '.github/ISSUE_TEMPLATE/bug_report.md',
            '.github/workflows/my_pkg.yaml',
            '.github/workflows/my_pkg_license_check.yaml',
          ]),
        );
        expect(summary.warnings, isEmpty);
        expect(
          Directory(path.join(package.path, '.github')).existsSync(),
          isFalse,
        );
      });

      test('points package ecosystems at the package directory', () {
        integrate();

        final dependabot =
            loadYaml(readRoot('dependabot.yaml')) as Map<dynamic, dynamic>;
        final updates = (dependabot['updates'] as List)
            .cast<Map<dynamic, dynamic>>();
        expect(
          updates.singleWhere(
            (u) => u['package-ecosystem'] == 'github-actions',
          )['directory'],
          equals('/'),
        );
        expect(
          updates.singleWhere(
            (u) => u['package-ecosystem'] == 'pub',
          )['directory'],
          equals('/packages/my_pkg'),
        );
      });

      test('scopes the relocated workflow to the package', () {
        integrate();

        final workflow =
            loadYaml(readRoot('workflows/my_pkg.yaml'))
                as Map<dynamic, dynamic>;
        expect(workflow['name'], equals('my_pkg'));

        final on = workflow['on'] as Map<dynamic, dynamic>;
        for (final trigger in ['push', 'pull_request']) {
          expect(
            (on[trigger] as Map<dynamic, dynamic>)['paths'],
            equals([
              'packages/my_pkg/**',
              '.github/workflows/my_pkg.yaml',
            ]),
          );
        }

        final jobs = workflow['jobs'] as Map<dynamic, dynamic>;
        expect(
          (jobs['semantic_pull_request'] as Map<dynamic, dynamic>)['with'],
          isNull,
        );
        expect(
          ((jobs['spell-check'] as Map<dynamic, dynamic>)['with']
              as Map<dynamic, dynamic>)['includes'],
          equals('packages/my_pkg/**/*.md'),
        );
        expect(
          ((jobs['build'] as Map<dynamic, dynamic>)['with']
              as Map<dynamic, dynamic>)['working_directory'],
          equals('packages/my_pkg'),
        );
      });

      test('rewrites existing workflow path filters', () {
        integrate();

        final workflow =
            loadYaml(readRoot('workflows/my_pkg_license_check.yaml'))
                as Map<dynamic, dynamic>;
        expect(workflow['name'], equals('my_pkg_license_check'));

        final pullRequest =
            (workflow['on'] as Map<dynamic, dynamic>)['pull_request']
                as Map<dynamic, dynamic>;
        expect(
          pullRequest['paths'],
          equals([
            'packages/my_pkg/pubspec.yaml',
            '.github/workflows/my_pkg_license_check.yaml',
          ]),
        );

        final jobs = workflow['jobs'] as Map<dynamic, dynamic>;
        expect(
          ((jobs['license_check'] as Map<dynamic, dynamic>)['with']
              as Map<dynamic, dynamic>)['working_directory'],
          equals('packages/my_pkg'),
        );
      });
    });

    group('with an existing root .github', () {
      test('appends missing dependabot entries and enables beta', () {
        writeSource('dependabot.yaml', _dependabot);
        writeRoot('dependabot.yaml', '''
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
''');

        final summary = integrate();

        expect(summary.merged, contains('.github/dependabot.yaml'));
        final dependabot =
            loadYaml(readRoot('dependabot.yaml')) as Map<dynamic, dynamic>;
        expect(dependabot['enable-beta-ecosystems'], isTrue);
        final updates = (dependabot['updates'] as List)
            .cast<Map<dynamic, dynamic>>();
        expect(updates, hasLength(2));
        // The existing entry is respected (schedule untouched).
        expect(
          updates.first['schedule'],
          equals({'interval': 'weekly'}),
        );
        expect(
          updates.last['directory'],
          equals('/packages/my_pkg'),
        );
      });

      test('creates the updates list when the root file lacks it', () {
        writeSource('dependabot.yaml', _dependabot);
        writeRoot('dependabot.yaml', 'version: 2\n');

        final summary = integrate();

        expect(summary.merged, contains('.github/dependabot.yaml'));
        final dependabot =
            loadYaml(readRoot('dependabot.yaml')) as Map<dynamic, dynamic>;
        expect(dependabot['version'], equals(2));
        expect(dependabot['updates'], hasLength(2));
      });

      test('cspell merge is idempotent', () {
        writeSource('cspell.json', _cspell);
        writeRoot('cspell.json', _cspell);

        final summary = integrate();

        expect(summary.skipped, contains('.github/cspell.json'));
        expect(summary.merged, isEmpty);
      });

      test('dependabot merge is idempotent', () {
        writeSource('dependabot.yaml', _dependabot);
        writeRoot('dependabot.yaml', '''
version: 2
enable-beta-ecosystems: true
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "daily"
  - package-ecosystem: "pub"
    directory: "/packages/my_pkg"
    schedule:
      interval: "daily"
''');

        final summary = integrate();

        expect(summary.skipped, contains('.github/dependabot.yaml'));
        expect(summary.merged, isEmpty);
      });

      test('merges the Very Good dictionaries and words into cspell', () {
        writeSource('cspell.json', _cspell);
        writeRoot('cspell.json', r'''
{
  "version": "0.2",
  "$schema": "https://example.com/wrong.schema.json",
  "dictionaries": ["custom"],
  "words": ["existing"]
}
''');

        final summary = integrate();

        expect(summary.merged, contains('.github/cspell.json'));
        final cspell =
            json.decode(readRoot('cspell.json')) as Map<String, dynamic>;
        expect(
          cspell[r'$schema'],
          equals(
            'https://raw.githubusercontent.com/streetsidesoftware/cspell/main/cspell.schema.json',
          ),
        );
        expect(
          cspell['dictionaries'],
          equals(['custom', 'vgv_allowed', 'vgv_forbidden']),
        );
        expect(cspell['words'], equals(['existing', 'my_pkg']));
        expect(
          (cspell['dictionaryDefinitions'] as List).length,
          equals(2),
        );
      });

      test('warns and leaves the source when root cspell is unparseable', () {
        writeSource('cspell.json', _cspell);
        writeRoot('cspell.json', '// JSONC comment\n{"version": "0.2"}');

        final summary = integrate();

        expect(summary.warnings, hasLength(1));
        expect(
          File(
            path.join(package.path, '.github', 'cspell.json'),
          ).existsSync(),
          isTrue,
        );
      });

      test('overwrites the pull request template', () {
        writeSource('PULL_REQUEST_TEMPLATE.md', '# New template\n');
        writeRoot('PULL_REQUEST_TEMPLATE.md', '# Old template\n');

        final summary = integrate();

        expect(
          summary.overwritten,
          contains('.github/PULL_REQUEST_TEMPLATE.md'),
        );
        expect(
          readRoot('PULL_REQUEST_TEMPLATE.md'),
          equals('# New template\n'),
        );
      });

      test('skips identical files', () {
        writeSource('PULL_REQUEST_TEMPLATE.md', '# Same\n');
        writeRoot('PULL_REQUEST_TEMPLATE.md', '# Same\n');

        final summary = integrate();

        expect(summary.skipped, contains('.github/PULL_REQUEST_TEMPLATE.md'));
        expect(summary.overwritten, isEmpty);
      });

      test('ensures blank issues stay disabled', () {
        writeSource('ISSUE_TEMPLATE/config.yml', 'blank_issues_enabled: false');
        writeRoot(
          'ISSUE_TEMPLATE/config.yml',
          'blank_issues_enabled: true\ncontact_links: []\n',
        );

        final summary = integrate();

        expect(summary.merged, contains('.github/ISSUE_TEMPLATE/config.yml'));
        final config =
            loadYaml(readRoot('ISSUE_TEMPLATE/config.yml'))
                as Map<dynamic, dynamic>;
        expect(config['blank_issues_enabled'], isFalse);
        expect(config['contact_links'], isEmpty);
      });

      test('leaves config.yml untouched when already disabled', () {
        writeSource('ISSUE_TEMPLATE/config.yml', 'blank_issues_enabled: false');
        writeRoot('ISSUE_TEMPLATE/config.yml', 'blank_issues_enabled: false\n');

        final summary = integrate();

        expect(summary.skipped, contains('.github/ISSUE_TEMPLATE/config.yml'));
      });

      test('overwrites config.yml when it is not a map', () {
        writeSource('ISSUE_TEMPLATE/config.yml', 'blank_issues_enabled: false');
        writeRoot('ISSUE_TEMPLATE/config.yml', 'not-a-map');

        final summary = integrate();

        expect(
          summary.overwritten,
          contains('.github/ISSUE_TEMPLATE/config.yml'),
        );
        expect(
          readRoot('ISSUE_TEMPLATE/config.yml'),
          equals('blank_issues_enabled: false'),
        );
      });

      test('suffixes the workflow name on residual conflicts', () {
        writeSource('workflows/main.yaml', _mainWorkflow);
        writeRoot('workflows/my_pkg.yaml', 'name: unrelated\n');

        final summary = integrate();

        expect(summary.moved, contains('.github/workflows/my_pkg_1.yaml'));
        expect(readRoot('workflows/my_pkg.yaml'), equals('name: unrelated\n'));
      });

      test('re-running the workflow relocation is idempotent', () {
        writeSource('workflows/main.yaml', _mainWorkflow);
        integrate();

        writeSource('workflows/main.yaml', _mainWorkflow);
        final summary = integrate();

        expect(summary.skipped, contains('.github/workflows/my_pkg.yaml'));
        expect(rootHas('workflows/my_pkg_1.yaml'), isFalse);
      });
    });
  });
}
