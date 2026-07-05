import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:universal_io/io.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Reusable Very Good workflows that must not receive a `working_directory`
/// input when a generated workflow is relocated to the repository root.
const _semanticPullRequestWorkflow = 'semantic_pull_request.yml';

/// The reusable Very Good spell check workflow. Its `config` input must keep
/// resolving at the repository root, so the relocation scopes its `includes`
/// glob instead of setting a `working_directory`.
const _spellCheckWorkflow = 'spell_check.yml';

/// The organization prefix of the reusable Very Good workflows.
const _veryGoodWorkflowsPrefix =
    'VeryGoodOpenSource/very_good_workflows/.github/workflows/';

/// {@template github_integration_summary}
/// The outcome of relocating a generated `.github` directory to the
/// repository root.
/// {@endtemplate}
class GithubIntegrationSummary {
  /// {@macro github_integration_summary}
  GithubIntegrationSummary();

  /// Files created at the repository root.
  final List<String> moved = [];

  /// Existing repository root files that were updated in place.
  final List<String> merged = [];

  /// Existing repository root files that were replaced.
  final List<String> overwritten = [];

  /// Files that required no change (already identical at the root).
  final List<String> skipped = [];

  /// Files that could not be integrated and were left in the package.
  final List<String> warnings = [];

  /// Whether the integration produced no output at all.
  bool get isEmpty =>
      moved.isEmpty &&
      merged.isEmpty &&
      overwritten.isEmpty &&
      skipped.isEmpty &&
      warnings.isEmpty;
}

/// {@template github_integrator}
/// Relocates a generated package-level `.github` directory to the root of the
/// surrounding git repository, resolving conflicts with any existing files.
///
/// GitHub only executes workflows from the repository root `.github`
/// directory, so metadata generated inside a nested package would otherwise
/// be inert.
///
/// Conflict resolution, per file:
///
/// * `dependabot.yaml`: existing version is respected and new entries are
///   appended to `updates` with the package's relative `directory`.
/// * `cspell.json`: the Very Good dictionaries and the package words are
///   merged into the existing configuration.
/// * `PULL_REQUEST_TEMPLATE.md` and `ISSUE_TEMPLATE/*.md`: overwritten; the
///   end user decides whether to commit or revert.
/// * `ISSUE_TEMPLATE/config.yml`: `blank_issues_enabled` is ensured disabled.
/// * `workflows/*`: renamed after the project (`main.yaml` becomes
///   `<project_name>.yaml`) with `_1`, `_2`… suffixes on residual conflicts,
///   and their triggers and inputs are scoped to the package directory.
/// {@endtemplate}
class GithubIntegrator {
  /// {@macro github_integrator}
  const GithubIntegrator();

  /// Integrates the `.github` directory generated in [packageDirectory] into
  /// [repositoryRoot], resolving conflicts. Returns a summary of the changes.
  GithubIntegrationSummary integrate({
    required Directory packageDirectory,
    required Directory repositoryRoot,
    required String projectName,
  }) {
    final summary = GithubIntegrationSummary();
    final sourceGithub = Directory(
      path.join(packageDirectory.path, '.github'),
    );
    if (!sourceGithub.existsSync()) return summary;

    final relativePath = path
        .split(
          path.relative(
            path.normalize(packageDirectory.absolute.path),
            from: path.normalize(repositoryRoot.absolute.path),
          ),
        )
        .join('/');

    final files =
        sourceGithub.listSync(recursive: true).whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final relative = path
          .split(path.relative(file.path, from: sourceGithub.path))
          .join('/');
      _integrateFile(
        file,
        relative: relative,
        rootGithub: Directory(path.join(repositoryRoot.path, '.github')),
        packagePath: relativePath,
        projectName: projectName,
        summary: summary,
      );
    }

    _pruneEmptyDirectories(sourceGithub);
    return summary;
  }

  /// Routes [source] to its conflict resolution strategy, overwriting
  /// `PULL_REQUEST_TEMPLATE.md`, `ISSUE_TEMPLATE/*.md`, and any unrecognized
  /// file completely so the end user decides to commit or revert.
  ///
  /// A malformed file at the repository root never fails project generation:
  /// it is reported as a warning and the generated file is left in the
  /// package instead.
  void _integrateFile(
    File source, {
    required String relative,
    required Directory rootGithub,
    required String packagePath,
    required String projectName,
    required GithubIntegrationSummary summary,
  }) {
    final basename = path.basename(relative);

    try {
      if (basename == 'dependabot.yaml' || basename == 'dependabot.yml') {
        _mergeDependabot(source, relative, rootGithub, packagePath, summary);
      } else if (basename == 'cspell.json') {
        _mergeCspell(source, relative, rootGithub, summary);
      } else if (relative.startsWith('workflows/')) {
        _relocateWorkflow(
          source,
          rootGithub: rootGithub,
          packagePath: packagePath,
          projectName: projectName,
          summary: summary,
        );
      } else if (basename == 'config.yml' || basename == 'config.yaml') {
        _mergeIssueTemplateConfig(source, relative, rootGithub, summary);
      } else {
        _overwrite(source, relative, rootGithub, summary);
      }
    } on Exception catch (error) {
      summary.warnings.add(
        'Could not integrate .github/$relative at the repository root '
        '($error); the generated file was left in the package.',
      );
    }
  }

  void _overwrite(
    File source,
    String relative,
    Directory rootGithub,
    GithubIntegrationSummary summary,
  ) {
    final target = File(path.join(rootGithub.path, relative));
    final content = source.readAsStringSync();
    final existed = target.existsSync();

    if (existed && target.readAsStringSync() == content) {
      summary.skipped.add('.github/$relative');
    } else {
      target
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
      (existed ? summary.overwritten : summary.moved).add('.github/$relative');
    }
    source.deleteSync();
  }

  /// Merges the generated dependabot configuration into the repository root.
  ///
  /// Package ecosystems are pointed at the package directory, while
  /// `github-actions` entries keep targeting `/` where the relocated
  /// workflows live. The existing `version` and entries are respected: new
  /// entries are only appended, and `enable-beta-ecosystems` is enabled when
  /// a `pub` entry (a Dependabot beta ecosystem) is added.
  void _mergeDependabot(
    File source,
    String relative,
    Directory rootGithub,
    String packagePath,
    GithubIntegrationSummary summary,
  ) {
    final sourceEditor = YamlEditor(source.readAsStringSync());
    final updates = sourceEditor.parseAt(['updates']) as YamlList;
    for (var i = 0; i < updates.length; i++) {
      final entry = updates[i] as YamlMap;
      if (entry['package-ecosystem'] != 'github-actions') {
        sourceEditor.update(['updates', i, 'directory'], '/$packagePath');
      }
    }

    final target = File(path.join(rootGithub.path, relative));
    if (!target.existsSync()) {
      target
        ..createSync(recursive: true)
        ..writeAsStringSync(sourceEditor.toString());
      summary.moved.add('.github/$relative');
      source.deleteSync();
      return;
    }

    final targetEditor = YamlEditor(target.readAsStringSync());
    final updatesNode = targetEditor.parseAt([
      'updates',
    ], orElse: () => wrapAsYamlNode(null)).value;
    final List<Map<dynamic, dynamic>> existing;
    if (updatesNode is List) {
      existing = updatesNode.cast<Map<dynamic, dynamic>>();
    } else {
      existing = const [];
      targetEditor.update(['updates'], <dynamic>[]);
    }
    bool isPresent(Map<dynamic, dynamic> entry) => existing.any(
      (candidate) =>
          candidate['package-ecosystem'] == entry['package-ecosystem'] &&
          candidate['directory'] == entry['directory'],
    );

    var appendedBetaEcosystem = false;
    final transformed =
        loadYaml(sourceEditor.toString()) as Map<dynamic, dynamic>;
    for (final entry
        in (transformed['updates'] as List).cast<Map<dynamic, dynamic>>()) {
      if (isPresent(entry)) continue;
      targetEditor.appendToList(
        ['updates'],
        json.decode(json.encode(entry)),
      );
      appendedBetaEcosystem =
          appendedBetaEcosystem || entry['package-ecosystem'] == 'pub';
    }

    final betaEnabled =
        targetEditor.parseAt(
          ['enable-beta-ecosystems'],
          orElse: () => wrapAsYamlNode(null),
        ).value ==
        true;
    if (appendedBetaEcosystem && !betaEnabled) {
      targetEditor.update(['enable-beta-ecosystems'], true);
    }

    final result = targetEditor.toString();
    if (result == target.readAsStringSync()) {
      summary.skipped.add('.github/$relative');
    } else {
      target.writeAsStringSync(result);
      summary.merged.add('.github/$relative');
    }
    source.deleteSync();
  }

  /// Merges the generated cspell configuration into the repository root: the
  /// schema is corrected when it differs, and the Very Good dictionaries,
  /// their definitions, and the package words are added when missing.
  void _mergeCspell(
    File source,
    String relative,
    Directory rootGithub,
    GithubIntegrationSummary summary,
  ) {
    final target = File(path.join(rootGithub.path, relative));
    if (!target.existsSync()) {
      _overwrite(source, relative, rootGithub, summary);
      return;
    }

    final sourceConfig =
        json.decode(source.readAsStringSync()) as Map<String, dynamic>;
    final Map<String, dynamic> targetConfig;
    try {
      targetConfig =
          json.decode(target.readAsStringSync()) as Map<String, dynamic>;
    } on FormatException {
      summary.warnings.add(
        'Could not parse ${path.join('.github', relative)} at the repository '
        'root; the generated one was left in the package.',
      );
      return;
    }

    final original = json.encode(targetConfig);

    if (sourceConfig[r'$schema'] != null &&
        targetConfig[r'$schema'] != sourceConfig[r'$schema']) {
      targetConfig[r'$schema'] = sourceConfig[r'$schema'];
    }

    for (final key in ['dictionaries', 'words']) {
      final sourceValues = (sourceConfig[key] as List? ?? []).cast<String>();
      final targetValues = [
        ...(targetConfig[key] as List? ?? []).cast<String>(),
      ];
      targetValues.addAll(
        sourceValues.where((value) => !targetValues.contains(value)),
      );
      if (targetValues.isNotEmpty) targetConfig[key] = targetValues;
    }
    final sourceDefinitions =
        (sourceConfig['dictionaryDefinitions'] as List? ?? [])
            .cast<Map<String, dynamic>>();
    final targetDefinitions = [
      ...(targetConfig['dictionaryDefinitions'] as List? ?? [])
          .cast<Map<String, dynamic>>(),
    ];
    targetDefinitions.addAll(
      sourceDefinitions.where(
        (definition) => !targetDefinitions.any(
          (candidate) => candidate['name'] == definition['name'],
        ),
      ),
    );
    if (targetDefinitions.isNotEmpty) {
      targetConfig['dictionaryDefinitions'] = targetDefinitions;
    }

    if (json.encode(targetConfig) == original) {
      summary.skipped.add('.github/$relative');
    } else {
      target.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(targetConfig)}\n',
      );
      summary.merged.add('.github/$relative');
    }
    source.deleteSync();
  }

  void _mergeIssueTemplateConfig(
    File source,
    String relative,
    Directory rootGithub,
    GithubIntegrationSummary summary,
  ) {
    final target = File(path.join(rootGithub.path, relative));
    if (!target.existsSync()) {
      _overwrite(source, relative, rootGithub, summary);
      return;
    }

    final content = target.readAsStringSync();
    if (loadYaml(content) is! Map) {
      _overwrite(source, relative, rootGithub, summary);
      return;
    }

    final editor = YamlEditor(content)..update(['blank_issues_enabled'], false);
    final result = editor.toString();
    if (result == content) {
      summary.skipped.add('.github/$relative');
    } else {
      target.writeAsStringSync(result);
      summary.merged.add('.github/$relative');
    }
    source.deleteSync();
  }

  /// Relocates a generated workflow to the repository root under a
  /// project-scoped name: `main.yaml` becomes `<project_name>.yaml`, other
  /// workflows keep their purpose in the name (e.g.
  /// `<project_name>_license_check.yaml`), and workflows already named after
  /// the project keep their names. Residual conflicts are resolved with
  /// `_1`, `_2`… suffixes, and identical files are skipped so re-runs stay
  /// idempotent.
  void _relocateWorkflow(
    File source, {
    required Directory rootGithub,
    required String packagePath,
    required String projectName,
    required GithubIntegrationSummary summary,
  }) {
    final basename = path.basename(source.path);
    final extension = path.extension(basename);
    final stem = path.basenameWithoutExtension(basename);
    final alreadyNamedAfterProject =
        stem == projectName || stem.startsWith('${projectName}_');
    final base = stem == 'main'
        ? projectName
        : alreadyNamedAfterProject
        ? stem
        : '${projectName}_$stem';
    final content = source.readAsStringSync();

    for (var attempt = 0; ; attempt++) {
      final candidate = attempt == 0
          ? '$base$extension'
          : '${base}_$attempt$extension';
      final transformed = _transformWorkflow(
        content,
        workflowFileName: candidate,
        packagePath: packagePath,
      );
      final target = File(path.join(rootGithub.path, 'workflows', candidate));

      if (target.existsSync()) {
        if (target.readAsStringSync() != transformed) continue;
        summary.skipped.add('.github/workflows/$candidate');
      } else {
        target
          ..createSync(recursive: true)
          ..writeAsStringSync(transformed);
        summary.moved.add('.github/workflows/$candidate');
      }
      source.deleteSync();
      return;
    }
  }

  /// Rewrites a generated workflow so it works from the repository root: a
  /// unique name (which also keeps the `github.workflow` derived concurrency
  /// group isolated per package), `push`/`pull_request` triggers scoped to
  /// the package — including the scalar form (`on: pull_request`) used by the
  /// docs site template — and jobs pointed at the package directory.
  String _transformWorkflow(
    String content, {
    required String workflowFileName,
    required String packagePath,
  }) {
    final editor = YamlEditor(content);
    final workflow = loadYaml(content) as YamlMap;

    editor.update(['name'], path.basenameWithoutExtension(workflowFileName));

    final triggers = workflow['on'];
    final defaultPaths = [
      '$packagePath/**',
      '.github/workflows/$workflowFileName',
    ];
    for (final trigger in ['push', 'pull_request']) {
      if (triggers is String && triggers == trigger) {
        editor.update(
          ['on'],
          {
            trigger: {'paths': defaultPaths},
          },
        );
      } else if (triggers is YamlMap && triggers.containsKey(trigger)) {
        final definition = triggers[trigger] as YamlMap?;
        final paths = definition?['paths'] as YamlList?;
        final scoped = paths == null
            ? defaultPaths
            : [
                for (final entry in paths.cast<String>())
                  entry.startsWith('.github/')
                      ? '.github/workflows/$workflowFileName'
                      : '$packagePath/$entry',
              ];
        editor.update(
          ['on', trigger],
          json.decode(json.encode({...?definition, 'paths': scoped})),
        );
      }
    }

    final jobs = workflow['jobs'] as YamlMap? ?? YamlMap();
    for (final entry in jobs.entries) {
      final job = entry.value;
      if (job is! YamlMap) continue;
      final uses = job['uses'] as String?;

      if (uses == null) {
        _scopePlainJob(editor, entry.key, job, packagePath);
      } else if (uses.startsWith(_veryGoodWorkflowsPrefix)) {
        _scopeReusableWorkflowJob(editor, entry.key, job, uses, packagePath);
      }
    }

    return editor.toString();
  }

  /// Points a job that calls a reusable Very Good workflow at the package
  /// directory, preserving (and prefixing) any inputs the template already
  /// provides.
  void _scopeReusableWorkflowJob(
    YamlEditor editor,
    Object? jobName,
    YamlMap job,
    String uses,
    String packagePath,
  ) {
    final reusableWorkflow = path.basename(uses.split('@').first);
    if (reusableWorkflow == _semanticPullRequestWorkflow) return;

    final existingInputs = job['with'] as YamlMap?;
    final Map<String, dynamic> scopedInputs;
    if (reusableWorkflow == _spellCheckWorkflow) {
      final includes = existingInputs?['includes'] as String? ?? '**/*.md';
      scopedInputs = {'includes': '$packagePath/$includes'};
    } else {
      final workingDirectory = existingInputs?['working_directory'] as String?;
      scopedInputs = {
        'working_directory': workingDirectory == null
            ? packagePath
            : '$packagePath/$workingDirectory',
      };
    }

    editor.update(
      ['jobs', jobName, 'with'],
      json.decode(json.encode({...?existingInputs, ...scopedInputs})),
    );
  }

  /// Scopes a job that runs its own steps (no reusable workflow) to the
  /// package directory via `defaults.run.working-directory`, preserving (and
  /// prefixing) any working directory the template already declares. Step
  /// inputs that resolve from the repository root (`cache-dependency-path`)
  /// are prefixed as well.
  void _scopePlainJob(
    YamlEditor editor,
    Object? jobName,
    YamlMap job,
    String packagePath,
  ) {
    final defaults = job['defaults'] as YamlMap?;
    final run = defaults?['run'] as YamlMap?;
    final workingDirectory = run?['working-directory'] as String?;
    editor.update(
      ['jobs', jobName, 'defaults'],
      json.decode(
        json.encode({
          ...?defaults,
          'run': {
            ...?run,
            'working-directory': workingDirectory == null
                ? packagePath
                : '$packagePath/$workingDirectory',
          },
        }),
      ),
    );

    final steps = job['steps'] as YamlList? ?? YamlList();
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      if (step is! YamlMap) continue;
      final inputs = step['with'] as YamlMap?;
      final dependencyPath = inputs?['cache-dependency-path'];
      if (dependencyPath is String) {
        editor.update(
          ['jobs', jobName, 'steps', i, 'with', 'cache-dependency-path'],
          '$packagePath/$dependencyPath',
        );
      }
    }
  }

  void _pruneEmptyDirectories(Directory directory) {
    if (!directory.existsSync()) return;
    directory.listSync().whereType<Directory>().forEach(_pruneEmptyDirectories);
    if (directory.listSync().isEmpty) directory.deleteSync();
  }
}
