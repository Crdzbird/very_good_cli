import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:very_good_cli/src/commands/create/commands/create_subcommand.dart';
import 'package:very_good_cli/src/commands/create/templates/template.dart';
import 'package:very_good_cli/src/github/github.dart';

class _MockTemplate extends Mock implements Template {}

class _MockGitRootDetector extends Mock implements GitRootDetector {}

class _MockGithubIntegrator extends Mock implements GithubIntegrator {}

class _MockLogger extends Mock implements Logger {}

class _MockProgress extends Mock implements Progress {}

class _MockMasonGenerator extends Mock implements MasonGenerator {}

class _MockBundle extends Mock implements MasonBundle {}

class _MockGeneratorHooks extends Mock implements GeneratorHooks {}

class _FakeLogger extends Fake implements Logger {}

class _FakeDirectoryGeneratorTarget extends Fake
    implements DirectoryGeneratorTarget {}

class _FakeDirectory extends Fake implements Directory {}

class _TestCreateSubCommand extends CreateSubCommand {
  _TestCreateSubCommand({
    required this.template,
    required super.logger,
    required super.generatorFromBundle,
    super.gitRootDetector,
    super.githubIntegrator,
  });

  @override
  final String name = 'create_subcommand';

  @override
  final String description = 'Create command';

  @override
  final Template template;
}

class _TestCreateSubCommandWithOrgName extends _TestCreateSubCommand
    with OrgName {
  _TestCreateSubCommandWithOrgName({
    required super.template,
    required super.logger,
    required super.generatorFromBundle,
  });
}

class _TestCreateSubCommandWithPublishable extends _TestCreateSubCommand
    with Publishable {
  _TestCreateSubCommandWithPublishable({
    required super.template,
    required super.logger,
    required super.generatorFromBundle,
  });
}

class _TestCreateSubCommandMultiTemplate extends CreateSubCommand
    with MultiTemplates {
  _TestCreateSubCommandMultiTemplate({
    required this.templates,
    required super.logger,
    required super.generatorFromBundle,
  });

  @override
  final String name = 'create_subcommand';

  @override
  final String description = 'Create command';

  @override
  final List<Template> templates;
}

class _TestCommandRunner extends CommandRunner<int> {
  _TestCommandRunner({required this.command})
    : super('runner', 'Test command runner') {
    addCommand(command);
  }

  final Command<int> command;
}

void main() {
  final generatedFiles = List.filled(10, const GeneratedFile.created(path: ''));

  late List<String> progressLogs;
  late Logger logger;
  late Progress progress;

  setUpAll(() {
    registerFallbackValue(_FakeDirectoryGeneratorTarget());
    registerFallbackValue(_FakeLogger());
    registerFallbackValue(_FakeDirectory());
  });

  setUp(() {
    progressLogs = <String>[];

    logger = _MockLogger();

    progress = _MockProgress();
    when(() => progress.complete(any())).thenAnswer((invocation) {
      final message = invocation.positionalArguments.first as String?;
      if (message != null) progressLogs.add(message);
    });
    when(() => logger.progress(any())).thenReturn(progress);
  });

  group('CreateSubCommand', () {
    const expectedUsage = '''
Usage: very_good create create_subcommand <project-name> [arguments]
-h, --help                Print this usage information.
-o, --output-directory    The desired output directory when creating a new project.
    --description         The description for this new project.
                          (defaults to "A Very Good Project created by Very Good CLI.")
    --[no-]workspace      Generate the project pre-configured as a pub workspace member.

Run "runner help" to see global options.''';

    late Template template;
    late _MockBundle bundle;

    setUp(() {
      bundle = _MockBundle();
      when(() => bundle.name).thenReturn('test');
      when(() => bundle.description).thenReturn('Test bundle');
      when(() => bundle.version).thenReturn('<bundleversion>');
      template = _MockTemplate();
      when(() => template.name).thenReturn('test');
      when(() => template.bundle).thenReturn(bundle);
      when(
        () => template.onGenerateComplete(any(), any()),
      ).thenAnswer((_) async {});
    });

    group('can be instantiated', () {
      test('with default options', () {
        final command = _TestCreateSubCommand(
          template: template,
          logger: logger,
          generatorFromBundle: null,
        );
        expect(command.name, isNotNull);
        expect(command.description, isNotNull);
        expect(command.argParser.options, {
          'help': isA<Option>(),
          'output-directory': isA<Option>()
              .having((o) => o.isSingle, 'isSingle', true)
              .having((o) => o.abbr, 'abbr', 'o')
              .having((o) => o.defaultsTo, 'defaultsTo', null)
              .having((o) => o.mandatory, 'mandatory', false),
          'description': isA<Option>()
              .having((o) => o.isSingle, 'isSingle', true)
              .having((o) => o.abbr, 'abbr', null)
              .having(
                (o) => o.defaultsTo,
                'defaultsTo',
                'A Very Good Project created by Very Good CLI.',
              )
              .having((o) => o.mandatory, 'mandatory', false),
          'workspace': isA<Option>()
              .having((o) => o.isFlag, 'isFlag', true)
              .having((o) => o.defaultsTo, 'defaultsTo', false),
        });
        expect(command.argParser.commands, isEmpty);
      });
    });

    group('running command', () {
      late GeneratorHooks hooks;
      late MasonGenerator generator;

      late _TestCommandRunner runner;

      setUp(() {
        hooks = _MockGeneratorHooks();
        generator = _MockMasonGenerator();

        when(() => generator.hooks).thenReturn(hooks);
        when(
          () => hooks.preGen(
            vars: any(named: 'vars'),
            onVarsChanged: any(named: 'onVarsChanged'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => generator.generate(
            any(),
            vars: any(named: 'vars'),
            logger: any(named: 'logger'),
          ),
        ).thenAnswer((_) async {
          return generatedFiles;
        });

        when(() => generator.id).thenReturn('generator_id');
        when(() => generator.description).thenReturn('generator description');
        when(() => generator.hooks).thenReturn(hooks);

        when(
          () => hooks.preGen(
            vars: any(named: 'vars'),
            onVarsChanged: any(named: 'onVarsChanged'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => generator.generate(
            any(),
            vars: any(named: 'vars'),
            logger: any(named: 'logger'),
          ),
        ).thenAnswer((_) async {
          return generatedFiles;
        });

        final command = _TestCreateSubCommand(
          template: template,
          logger: logger,
          generatorFromBundle: (_) async => generator,
        );

        runner = _TestCommandRunner(command: command);
      });

      group('parsing of options', () {
        group('for project name', () {
          test(
            'uses current directory basename as name if . provided',
            () async {
              final expectedProjectName = path.basename(Directory.current.path);

              final result = await runner.run(['create_subcommand', '.']);

              expect(result, equals(ExitCode.success.code));
              verify(() => logger.progress('Bootstrapping')).called(1);

              verify(
                () => hooks.preGen(
                  vars: <String, dynamic>{
                    'project_name': expectedProjectName,
                    'description':
                        'A Very Good Project created by Very Good CLI.',
                    'workspace': false,
                  },
                  onVarsChanged: any(named: 'onVarsChanged'),
                ),
              );
            },
          );

          test('uses name if just a name is provided', () async {
            final result = await runner.run(['create_subcommand', 'name']);

            expect(result, equals(ExitCode.success.code));
            verify(() => logger.progress('Bootstrapping')).called(1);

            verify(
              () => hooks.preGen(
                vars: <String, dynamic>{
                  'project_name': 'name',
                  'description':
                      'A Very Good Project created by Very Good CLI.',
                  'workspace': false,
                },
                onVarsChanged: any(named: 'onVarsChanged'),
              ),
            );
          });
        });

        test(
          'allows projects to be created in the current directory using .',
          () async {
            final expectedProjectName = path.basename(Directory.current.path);

            final result = await runner.run(['create_subcommand', '.']);

            expect(result, equals(ExitCode.success.code));
            verify(() => logger.progress('Bootstrapping')).called(1);

            verify(
              () => hooks.preGen(
                vars: <String, dynamic>{
                  'project_name': expectedProjectName,
                  'description':
                      'A Very Good Project created by Very Good CLI.',
                  'workspace': false,
                },
                onVarsChanged: any(named: 'onVarsChanged'),
              ),
            );

            verify(
              () => generator.generate(
                any(
                  that: isA<DirectoryGeneratorTarget>().having(
                    (g) {
                      return g.dir.path;
                    },
                    'dir',
                    '.',
                  ),
                ),
                vars: <String, dynamic>{
                  'project_name': expectedProjectName,
                  'description':
                      'A Very Good Project created by Very Good CLI.',
                  'workspace': false,
                },
                logger: logger,
              ),
            ).called(1);

            expect(
              progressLogs,
              equals(['Generated ${generatedFiles.length} file(s)']),
            );

            verify(
              () => template.onGenerateComplete(
                logger,
                any(
                  that: isA<Directory>().having(
                    (d) {
                      return d.path;
                    },
                    'path',
                    '.',
                  ),
                ),
              ),
            ).called(1);
          },
        );

        test('uses default values for omitted options', () async {
          final result = await runner.run([
            'create_subcommand',
            'test_project',
          ]);

          expect(result, equals(ExitCode.success.code));
          verify(() => logger.progress('Bootstrapping')).called(1);

          verify(() {
            return hooks.preGen(
              vars: <String, dynamic>{
                'project_name': 'test_project',
                'description': 'A Very Good Project created by Very Good CLI.',
                'workspace': false,
              },
              onVarsChanged: any(named: 'onVarsChanged'),
            );
          });

          verify(
            () => generator.generate(
              any(
                that: isA<DirectoryGeneratorTarget>().having(
                  (g) {
                    return g.dir.path;
                  },
                  'dir',
                  'test_project',
                ),
              ),
              vars: <String, dynamic>{
                'project_name': 'test_project',
                'description': 'A Very Good Project created by Very Good CLI.',
                'workspace': false,
              },
              logger: logger,
            ),
          ).called(1);

          verify(
            () => template.onGenerateComplete(
              logger,
              any(
                that: isA<Directory>().having(
                  (d) {
                    return d.path;
                  },
                  'path',
                  'test_project',
                ),
              ),
            ),
          ).called(1);
        });

        group('validates project name', () {
          test(
            'throws UsageException when project-name contains "/"',
            () async {
              await expectLater(
                () async {
                  await runner.run(['create_subcommand', 'path/to/name']);
                },
                throwsA(
                  isA<UsageException>()
                      .having((e) => e.usage, 'usage', expectedUsage)
                      .having(
                        (e) => e.message,
                        'message',
                        'Project name cannot contain "/".',
                      ),
                ),
              );
            },
          );

          test('throws UsageException when project-name is . and '
              '--output-directory is provided', () async {
            await expectLater(
              () async {
                await runner.run([
                  'create_subcommand',
                  '.',
                  '--output-directory',
                  'path/to/name',
                ]);
              },
              throwsA(
                isA<UsageException>()
                    .having((e) => e.usage, 'usage', expectedUsage)
                    .having(
                      (e) => e.message,
                      'message',
                      '''--output-directory cannot be specified when using "very_good create <template> ."''',
                    ),
              ),
            );
          });
          test('throws UsageException when project-name is omitted', () async {
            await expectLater(
              () async {
                await runner.run([
                  'create_subcommand',
                  '--description="some description"',
                ]);
              },
              throwsA(
                isA<UsageException>()
                    .having((e) => e.usage, 'usage', expectedUsage)
                    .having(
                      (e) => e.message,
                      'message',
                      'No option specified for the project name.',
                    ),
              ),
            );
          });

          test('throws UsageException when project-name is invalid', () async {
            await expectLater(
              () async {
                await runner.run(['create_subcommand', 'invalid-name']);
              },
              throwsA(
                isA<UsageException>()
                    .having((e) => e.usage, 'usage', expectedUsage)
                    .having((e) => e.message, 'message', '''
"invalid-name" is not a valid package name.

See https://dart.dev/tools/pub/pubspec#name for more information.'''),
              ),
            );
          });

          test(
            'throws UsageException when multiple project names are provided',
            () async {
              await expectLater(
                () async {
                  await runner.run(['create_subcommand', 'name', 'other_name']);
                },
                throwsA(
                  isA<UsageException>()
                      .having((e) => e.usage, 'usage', expectedUsage)
                      .having(
                        (e) => e.message,
                        'message',
                        'Multiple project names specified.',
                      ),
                ),
              );
            },
          );
        });
      });

      group('mason generator selection', () {
        test('generates from the bundled template', () async {
          MasonBundle? bundleUsed;
          final command = _TestCreateSubCommand(
            template: template,
            logger: logger,
            generatorFromBundle: (b) async {
              bundleUsed = b;
              return generator;
            },
          );

          runner = _TestCommandRunner(command: command);

          final result = await runner.run([
            'create_subcommand',
            'test_project',
          ]);

          expect(result, equals(ExitCode.success.code));
          expect(bundleUsed, same(bundle));

          verify(
            () => generator.generate(
              any(
                that: isA<DirectoryGeneratorTarget>().having(
                  (g) => g.dir.path,
                  'dir',
                  'test_project',
                ),
              ),
              vars: <String, dynamic>{
                'project_name': 'test_project',
                'description': 'A Very Good Project created by Very Good CLI.',
                'workspace': false,
              },
              logger: logger,
            ),
          ).called(1);
        });
      });

      test(
        'returns unavailable exit code when preGen times out',
        () async {
          when(
            () => hooks.preGen(
              vars: any(named: 'vars'),
              onVarsChanged: any(named: 'onVarsChanged'),
            ),
          ).thenAnswer((_) => Completer<void>().future);

          final result = await runner.run([
            'create_subcommand',
            'test_project',
          ]);

          expect(result, equals(ExitCode.unavailable.code));
          verify(() => progress.fail(any())).called(1);
          verify(
            () => logger.err(
              any(
                that: contains(
                  'Bootstrapping timed out after '
                  '${CreateSubCommand.preGenTimeout.inSeconds} seconds.',
                ),
              ),
            ),
          ).called(1);
          verifyNever(
            () => generator.generate(
              any(),
              vars: any(named: 'vars'),
              logger: any(named: 'logger'),
            ),
          );
        },
        timeout: Timeout(
          CreateSubCommand.preGenTimeout + const Duration(seconds: 5),
        ),
      );
    });
  });

  group('workspace flag', () {
    late Template template;
    late _MockBundle bundle;
    late GeneratorHooks hooks;
    late MasonGenerator generator;

    setUp(() {
      bundle = _MockBundle();
      when(() => bundle.name).thenReturn('test');
      when(() => bundle.description).thenReturn('Test bundle');
      when(() => bundle.version).thenReturn('<bundleversion>');
      template = _MockTemplate();
      when(() => template.name).thenReturn('test');
      when(() => template.bundle).thenReturn(bundle);
      when(
        () => template.onGenerateComplete(any(), any()),
      ).thenAnswer((_) async {});

      hooks = _MockGeneratorHooks();
      generator = _MockMasonGenerator();
      when(() => generator.hooks).thenReturn(hooks);
      when(() => generator.id).thenReturn('generator_id');
      when(() => generator.description).thenReturn('generator description');
      when(
        () => hooks.preGen(
          vars: any(named: 'vars'),
          onVarsChanged: any(named: 'onVarsChanged'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => generator.generate(
          any(),
          vars: any(named: 'vars'),
          logger: any(named: 'logger'),
        ),
      ).thenAnswer((_) async => generatedFiles);
    });

    test('forwards workspace: true to the template vars', () async {
      final command = _TestCreateSubCommand(
        template: template,
        logger: logger,
        generatorFromBundle: (_) async => generator,
      );

      final result = await _TestCommandRunner(command: command).run([
        'create_subcommand',
        'test_project',
        '--workspace',
      ]);

      expect(result, equals(ExitCode.success.code));
      verify(
        () => generator.generate(
          any(),
          vars: any(named: 'vars', that: containsPair('workspace', true)),
          logger: logger,
        ),
      ).called(1);
    });
  });

  group('github integration', () {
    late Template template;
    late _MockBundle bundle;
    late GeneratorHooks hooks;
    late MasonGenerator generator;
    late _MockGitRootDetector gitRootDetector;
    late _MockGithubIntegrator githubIntegrator;
    late Directory repositoryRoot;

    setUp(() {
      bundle = _MockBundle();
      when(() => bundle.name).thenReturn('test');
      when(() => bundle.description).thenReturn('Test bundle');
      when(() => bundle.version).thenReturn('<bundleversion>');
      template = _MockTemplate();
      when(() => template.name).thenReturn('test');
      when(() => template.bundle).thenReturn(bundle);
      when(
        () => template.onGenerateComplete(any(), any()),
      ).thenAnswer((_) async {});

      hooks = _MockGeneratorHooks();
      generator = _MockMasonGenerator();
      when(() => generator.hooks).thenReturn(hooks);
      when(() => generator.id).thenReturn('generator_id');
      when(() => generator.description).thenReturn('generator description');
      when(
        () => hooks.preGen(
          vars: any(named: 'vars'),
          onVarsChanged: any(named: 'onVarsChanged'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => generator.generate(
          any(),
          vars: any(named: 'vars'),
          logger: any(named: 'logger'),
        ),
      ).thenAnswer((_) async => generatedFiles);

      gitRootDetector = _MockGitRootDetector();
      githubIntegrator = _MockGithubIntegrator();
      repositoryRoot = Directory.systemTemp.createTempSync('vg_repo_');
      addTearDown(() => repositoryRoot.deleteSync(recursive: true));
    });

    _TestCommandRunner buildRunner() => _TestCommandRunner(
      command: _TestCreateSubCommand(
        template: template,
        logger: logger,
        generatorFromBundle: (_) async => generator,
        gitRootDetector: gitRootDetector,
        githubIntegrator: githubIntegrator,
      ),
    );

    test(
      'integrates the .github directory when generated inside a repository',
      () async {
        when(() => gitRootDetector.detect(any())).thenReturn(repositoryRoot);
        final summary = GithubIntegrationSummary()
          ..moved.add('.github/workflows/test_project.yaml')
          ..merged.add('.github/dependabot.yaml')
          ..overwritten.add('.github/PULL_REQUEST_TEMPLATE.md')
          ..warnings.add('Could not parse .github/cspell.json.');
        when(
          () => githubIntegrator.integrate(
            packageDirectory: any(named: 'packageDirectory'),
            repositoryRoot: any(named: 'repositoryRoot'),
            projectName: any(named: 'projectName'),
          ),
        ).thenReturn(summary);

        final result = await buildRunner().run([
          'create_subcommand',
          'test_project',
        ]);

        expect(result, equals(ExitCode.success.code));
        verify(
          () => githubIntegrator.integrate(
            packageDirectory: any(named: 'packageDirectory'),
            repositoryRoot: repositoryRoot,
            projectName: 'test_project',
          ),
        ).called(1);
        verify(
          () => logger.info(
            any(that: contains('Configured GitHub metadata')),
          ),
        ).called(1);
        verify(
          () => logger.info(
            any(that: contains('overwrote .github/PULL_REQUEST_TEMPLATE.md')),
          ),
        ).called(1);
        verify(
          () => logger.warn('Could not parse .github/cspell.json.'),
        ).called(1);
      },
    );

    test('does nothing when not inside a git repository', () async {
      when(() => gitRootDetector.detect(any())).thenReturn(null);

      final result = await buildRunner().run([
        'create_subcommand',
        'test_project',
      ]);

      expect(result, equals(ExitCode.success.code));
      verifyNever(
        () => githubIntegrator.integrate(
          packageDirectory: any(named: 'packageDirectory'),
          repositoryRoot: any(named: 'repositoryRoot'),
          projectName: any(named: 'projectName'),
        ),
      );
    });

    test('does nothing when the project is the repository root', () async {
      when(
        () => gitRootDetector.detect(any()),
      ).thenReturn(Directory('test_project'));

      final result = await buildRunner().run([
        'create_subcommand',
        'test_project',
      ]);

      expect(result, equals(ExitCode.success.code));
      verifyNever(
        () => githubIntegrator.integrate(
          packageDirectory: any(named: 'packageDirectory'),
          repositoryRoot: any(named: 'repositoryRoot'),
          projectName: any(named: 'projectName'),
        ),
      );
    });

    test('stays silent when there is nothing to integrate', () async {
      when(() => gitRootDetector.detect(any())).thenReturn(repositoryRoot);
      when(
        () => githubIntegrator.integrate(
          packageDirectory: any(named: 'packageDirectory'),
          repositoryRoot: any(named: 'repositoryRoot'),
          projectName: any(named: 'projectName'),
        ),
      ).thenReturn(GithubIntegrationSummary());

      final result = await buildRunner().run([
        'create_subcommand',
        'test_project',
      ]);

      expect(result, equals(ExitCode.success.code));
      verifyNever(
        () => logger.info(any(that: contains('Configured GitHub metadata'))),
      );
    });
  });

  group('OrgName', () {
    const expectedUsage = '''
Usage: very_good create create_subcommand <project-name> [arguments]
-h, --help                Print this usage information.
-o, --output-directory    The desired output directory when creating a new project.
    --description         The description for this new project.
                          (defaults to "A Very Good Project created by Very Good CLI.")
    --[no-]workspace      Generate the project pre-configured as a pub workspace member.
    --org-name            The organization for this new project.
                          (defaults to "com.example.verygoodcore")

Run "runner help" to see global options.''';

    late Template template;
    late _MockBundle bundle;

    setUp(() {
      bundle = _MockBundle();
      when(() => bundle.name).thenReturn('test');
      when(() => bundle.description).thenReturn('Test bundle');
      when(() => bundle.version).thenReturn('<bundleversion>');
      template = _MockTemplate();
      when(() => template.name).thenReturn('test');
      when(() => template.bundle).thenReturn(bundle);
      when(
        () => template.onGenerateComplete(any(), any()),
      ).thenAnswer((_) async {});
    });

    group('can be instantiated', () {
      test('with default options', () {
        final command = _TestCreateSubCommandWithOrgName(
          template: template,
          logger: logger,
          generatorFromBundle: null,
        );

        expect(
          command.argParser.options['org-name'],
          isA<Option>()
              .having((o) => o.isSingle, 'isSingle', true)
              .having((o) => o.abbr, 'abbr', null)
              .having(
                (o) => o.defaultsTo,
                'defaultsTo',
                'com.example.verygoodcore',
              )
              .having((o) => o.aliases, 'aliases', ['org']),
        );
        expect(command.argParser.commands, isEmpty);
      });
    });

    group('parsing of options', () {
      late GeneratorHooks hooks;
      late MasonGenerator generator;
      late _TestCommandRunner runner;

      setUp(() {
        hooks = _MockGeneratorHooks();
        generator = _MockMasonGenerator();

        when(() => generator.hooks).thenReturn(hooks);
        when(
          () => hooks.preGen(
            vars: any(named: 'vars'),
            onVarsChanged: any(named: 'onVarsChanged'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => generator.generate(
            any(),
            vars: any(named: 'vars'),
            logger: any(named: 'logger'),
          ),
        ).thenAnswer((_) async {
          return generatedFiles;
        });

        when(() => generator.id).thenReturn('generator_id');
        when(() => generator.description).thenReturn('generator description');
        when(() => generator.hooks).thenReturn(hooks);

        when(
          () => hooks.preGen(
            vars: any(named: 'vars'),
            onVarsChanged: any(named: 'onVarsChanged'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => generator.generate(
            any(),
            vars: any(named: 'vars'),
            logger: any(named: 'logger'),
          ),
        ).thenAnswer((_) async {
          return generatedFiles;
        });

        final command = _TestCreateSubCommandWithOrgName(
          template: template,
          logger: logger,
          generatorFromBundle: (_) async => generator,
        );

        runner = _TestCommandRunner(command: command);
      });

      test('parses org name', () async {
        final result = await runner.run([
          'create_subcommand',
          'test_project',
          '--org-name',
          'com.my.org',
        ]);

        expect(result, equals(ExitCode.success.code));

        verify(
          () => hooks.preGen(
            vars: any(
              named: 'vars',
              that: isA<Map<String, dynamic>>().having(
                (description) => description['org_name'],
                'org_name',
                'com.my.org',
              ),
            ),
            onVarsChanged: any(named: 'onVarsChanged'),
          ),
        );

        verify(
          () => generator.generate(
            any(that: isA<DirectoryGeneratorTarget>()),
            vars: any(
              named: 'vars',
              that: isA<Map<String, dynamic>>().having(
                (vars) {
                  return vars['org_name'];
                },
                'org_name',
                'com.my.org',
              ),
            ),
            logger: logger,
          ),
        ).called(1);
      });

      test('parses org name from alias', () async {
        final result = await runner.run([
          'create_subcommand',
          'test_project',
          '--org',
          'com.my.org',
        ]);

        expect(result, equals(ExitCode.success.code));

        verify(
          () => hooks.preGen(
            vars: any(
              named: 'vars',
              that: isA<Map<String, dynamic>>().having(
                (description) => description['org_name'],
                'org_name',
                'com.my.org',
              ),
            ),
            onVarsChanged: any(named: 'onVarsChanged'),
          ),
        );

        verify(
          () => generator.generate(
            any(that: isA<DirectoryGeneratorTarget>()),
            vars: any(
              named: 'vars',
              that: isA<Map<String, dynamic>>().having(
                (vars) {
                  return vars['org_name'];
                },
                'org_name',
                'com.my.org',
              ),
            ),
            logger: logger,
          ),
        ).called(1);
      });

      test('uses default values for omitted options', () async {
        final result = await runner.run(['create_subcommand', 'test_project']);

        expect(result, equals(ExitCode.success.code));

        verify(
          () => hooks.preGen(
            vars: any(
              named: 'vars',
              that: isA<Map<String, dynamic>>().having(
                (description) => description['org_name'],
                'org_name',
                'com.example.verygoodcore',
              ),
            ),
            onVarsChanged: any(named: 'onVarsChanged'),
          ),
        );

        verify(
          () => generator.generate(
            any(that: isA<DirectoryGeneratorTarget>()),
            vars: any(
              named: 'vars',
              that: isA<Map<String, dynamic>>().having(
                (vars) {
                  return vars['org_name'];
                },
                'org_name',
                'com.example.verygoodcore',
              ),
            ),
            logger: logger,
          ),
        ).called(1);
      });

      group('validates org name', () {
        test('throws UsageException when org-name has no delimiters', () async {
          await expectLater(
            () async {
              await runner.run([
                'create_subcommand',
                'test_project',
                '--org-name',
                'invalid org name',
              ]);
            },
            throwsA(
              isA<UsageException>()
                  .having((e) => e.usage, 'usage', expectedUsage)
                  .having((e) => e.message, 'message', '''
"invalid org name" is not a valid org name.

A valid org name has at least 2 parts separated by "."
Each part must start with a letter and only include alphanumeric characters (A-Z, a-z, 0-9), underscores (_), and hyphens (-)
(ex. very.good.org)'''),
            ),
          );
        });

        test(
          'throws UsageException when org-name has less than two levels',
          () async {
            await expectLater(
              () async {
                await runner.run([
                  'create_subcommand',
                  'test_project',
                  '--org-name',
                  'verybadtest',
                ]);
              },
              throwsA(
                isA<UsageException>()
                    .having((e) => e.usage, 'usage', expectedUsage)
                    .having((e) => e.message, 'message', '''
"verybadtest" is not a valid org name.

A valid org name has at least 2 parts separated by "."
Each part must start with a letter and only include alphanumeric characters (A-Z, a-z, 0-9), underscores (_), and hyphens (-)
(ex. very.good.org)'''),
              ),
            );
          },
        );

        test(
          'throws UsageException when org-name has invalid characters',
          () async {
            await expectLater(
              () async {
                await runner.run([
                  'create_subcommand',
                  'test_project',
                  '--org-name',
                  'very%.bad@.#test',
                ]);
              },
              throwsA(
                isA<UsageException>()
                    .having((e) => e.usage, 'usage', expectedUsage)
                    .having((e) => e.message, 'message', '''
"very%.bad@.#test" is not a valid org name.

A valid org name has at least 2 parts separated by "."
Each part must start with a letter and only include alphanumeric characters (A-Z, a-z, 0-9), underscores (_), and hyphens (-)
(ex. very.good.org)'''),
              ),
            );
          },
        );
      });
    });
  });
  group('MultiTemplates', () {
    const expectedUsage = '''
Usage: very_good create create_subcommand <project-name> [arguments]
-h, --help                         Print this usage information.
-o, --output-directory             The desired output directory when creating a new project.
    --description                  The description for this new project.
                                   (defaults to "A Very Good Project created by Very Good CLI.")
    --[no-]workspace               Generate the project pre-configured as a pub workspace member.
-t, --template                     The template used to generate this new project.

          [template1] (default)    template1 help
          [template2]              template2 help

Run "runner help" to see global options.''';

    late _MockBundle bundle;
    late List<Template> templates;

    setUp(() {
      bundle = _MockBundle();
      when(() => bundle.name).thenReturn('test');
      when(() => bundle.description).thenReturn('Test bundle');
      when(() => bundle.version).thenReturn('<bundleversion>');

      final template1 = _MockTemplate();
      when(() => template1.name).thenReturn('template1');
      when(() => template1.help).thenReturn('template1 help');
      when(() => template1.bundle).thenReturn(bundle);
      when(
        () => template1.onGenerateComplete(any(), any()),
      ).thenAnswer((_) async {});

      final template2 = _MockTemplate();
      when(() => template2.name).thenReturn('template2');
      when(() => template2.help).thenReturn('template2 help');
      when(() => template2.bundle).thenReturn(bundle);
      when(
        () => template2.onGenerateComplete(any(), any()),
      ).thenAnswer((_) async {});

      templates = [template1, template2];
    });

    group('can be instantiated', () {
      test('with default options', () {
        final command = _TestCreateSubCommandMultiTemplate(
          templates: templates,
          logger: logger,
          generatorFromBundle: null,
        );
        expect(
          command.argParser.options['template'],
          isA<Option>()
              .having((o) => o.isSingle, 'isSingle', true)
              .having((o) => o.abbr, 'abbr', 't')
              .having((o) => o.defaultsTo, 'defaultsTo', 'template1')
              .having((o) => o.allowed, 'allowed', ['template1', 'template2'])
              .having((o) => o.allowedHelp, 'allowedHelp', {
                'template1': 'template1 help',
                'template2': 'template2 help',
              }),
        );
        expect(command.argParser.commands, isEmpty);
      });
    });

    group('parsing of options', () {
      late GeneratorHooks hooks;
      late MasonGenerator generator;
      late _TestCommandRunner runner;

      setUp(() {
        hooks = _MockGeneratorHooks();
        generator = _MockMasonGenerator();

        when(() => generator.hooks).thenReturn(hooks);
        when(
          () => hooks.preGen(
            vars: any(named: 'vars'),
            onVarsChanged: any(named: 'onVarsChanged'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => generator.generate(
            any(),
            vars: any(named: 'vars'),
            logger: any(named: 'logger'),
          ),
        ).thenAnswer((_) async {
          return generatedFiles;
        });

        when(() => generator.id).thenReturn('generator_id');
        when(() => generator.description).thenReturn('generator description');
        when(() => generator.hooks).thenReturn(hooks);

        when(
          () => hooks.preGen(
            vars: any(named: 'vars'),
            onVarsChanged: any(named: 'onVarsChanged'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => generator.generate(
            any(),
            vars: any(named: 'vars'),
            logger: any(named: 'logger'),
          ),
        ).thenAnswer((_) async {
          return generatedFiles;
        });

        final command = _TestCreateSubCommandMultiTemplate(
          templates: templates,
          logger: logger,
          generatorFromBundle: (_) async => generator,
        );

        runner = _TestCommandRunner(command: command);
      });

      test('selects the correct template', () async {
        final result = await runner.run([
          'create_subcommand',
          'test_project',
          '--template',
          'template2',
        ]);
        expect(result, equals(ExitCode.success.code));
        final template1 = templates[0];
        final template2 = templates[1];
        verifyNever(() => template1.onGenerateComplete(logger, any()));
        verify(() => template2.onGenerateComplete(logger, any())).called(1);
      });

      test('selects the default template when omitted', () async {
        final result = await runner.run(['create_subcommand', 'test_project']);
        expect(result, equals(ExitCode.success.code));
        final template1 = templates[0];
        final template2 = templates[1];
        verify(() => template1.onGenerateComplete(logger, any())).called(1);
        verifyNever(() => template2.onGenerateComplete(logger, any()));
      });

      group('validates template name', () {
        test('throws UsageException when --template is invalid', () async {
          await expectLater(
            () async {
              await runner.run([
                'create_subcommand',
                'test_project',
                '--template',
                'template3',
              ]);
            },
            throwsA(
              isA<UsageException>()
                  .having((e) => e.usage, 'usage', expectedUsage)
                  .having(
                    (e) => e.message,
                    'message',
                    '"template3" is not an allowed value for option '
                        '"--template".',
                  ),
            ),
          );
        });
      });
    });
  });

  group('Publishable', () {
    const expectedUsage = '''
Usage: very_good create create_subcommand <project-name> [arguments]
-h, --help                Print this usage information.
-o, --output-directory    The desired output directory when creating a new project.
    --description         The description for this new project.
                          (defaults to "A Very Good Project created by Very Good CLI.")
    --[no-]workspace      Generate the project pre-configured as a pub workspace member.
    --publishable         Whether the generated project is intended to be published.

Run "runner help" to see global options.''';

    late Template template;
    late _MockBundle bundle;

    setUp(() {
      bundle = _MockBundle();
      when(() => bundle.name).thenReturn('test');
      when(() => bundle.description).thenReturn('Test bundle');
      when(() => bundle.version).thenReturn('<bundleversion>');
      template = _MockTemplate();
      when(() => template.name).thenReturn('test');
      when(() => template.bundle).thenReturn(bundle);
      when(
        () => template.onGenerateComplete(any(), any()),
      ).thenAnswer((_) async {});
    });

    group('can be instantiated', () {
      test('with default options', () {
        final command = _TestCreateSubCommandWithPublishable(
          template: template,
          logger: logger,
          generatorFromBundle: null,
        );

        expect(
          command.argParser.options['publishable'],
          isA<Option>()
              .having((o) => o.isFlag, 'isFlag', true)
              .having((o) => o.abbr, 'abbr', null)
              .having((o) => o.defaultsTo, 'defaultsTo', false)
              .having((o) => o.aliases, 'aliases', <String>[]),
        );
        expect(command.argParser.commands, isEmpty);
      });
    });

    group('parsing of options', () {
      late GeneratorHooks hooks;
      late MasonGenerator generator;
      late _TestCommandRunner runner;

      setUp(() {
        hooks = _MockGeneratorHooks();
        generator = _MockMasonGenerator();

        when(() => generator.hooks).thenReturn(hooks);
        when(
          () => hooks.preGen(
            vars: any(named: 'vars'),
            onVarsChanged: any(named: 'onVarsChanged'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => generator.generate(
            any(),
            vars: any(named: 'vars'),
            logger: any(named: 'logger'),
          ),
        ).thenAnswer((_) async {
          return generatedFiles;
        });

        when(() => generator.id).thenReturn('generator_id');
        when(() => generator.description).thenReturn('generator description');
        when(() => generator.hooks).thenReturn(hooks);

        when(
          () => hooks.preGen(
            vars: any(named: 'vars'),
            onVarsChanged: any(named: 'onVarsChanged'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => generator.generate(
            any(),
            vars: any(named: 'vars'),
            logger: any(named: 'logger'),
          ),
        ).thenAnswer((_) async {
          return generatedFiles;
        });

        final command = _TestCreateSubCommandWithPublishable(
          template: template,
          logger: logger,
          generatorFromBundle: (_) async => generator,
        );

        runner = _TestCommandRunner(command: command);
      });

      test('parses publishable', () async {
        final result = await runner.run([
          'create_subcommand',
          'test_project',
          '--publishable',
        ]);

        expect(result, equals(ExitCode.success.code));

        verify(
          () => hooks.preGen(
            vars: any(
              named: 'vars',
              that: isA<Map<String, dynamic>>().having(
                (description) => description['publishable'],
                'publishable',
                true,
              ),
            ),
            onVarsChanged: any(named: 'onVarsChanged'),
          ),
        );

        verify(
          () => generator.generate(
            any(that: isA<DirectoryGeneratorTarget>()),
            vars: any(
              named: 'vars',
              that: isA<Map<String, dynamic>>().having(
                (vars) {
                  return vars['publishable'];
                },
                'publishable',
                true,
              ),
            ),
            logger: logger,
          ),
        ).called(1);
      });

      test('uses default values for omitted options', () async {
        final result = await runner.run(['create_subcommand', 'test_project']);

        expect(result, equals(ExitCode.success.code));

        verify(
          () => hooks.preGen(
            vars: any(
              named: 'vars',
              that: isA<Map<String, dynamic>>().having(
                (description) => description['publishable'],
                'publishable',
                false,
              ),
            ),
            onVarsChanged: any(named: 'onVarsChanged'),
          ),
        );

        verify(
          () => generator.generate(
            any(that: isA<DirectoryGeneratorTarget>()),
            vars: any(
              named: 'vars',
              that: isA<Map<String, dynamic>>().having(
                (description) => description['publishable'],
                'publishable',
                false,
              ),
            ),
            logger: logger,
          ),
        ).called(1);
      });

      group('validates publishable', () {
        test('throws UsageException when --template is invalid', () async {
          await expectLater(
            () async {
              await runner.run([
                'create_subcommand',
                'test_project',
                '--no-publishable',
              ]);
            },
            throwsA(
              isA<UsageException>()
                  .having((e) => e.usage, 'usage', expectedUsage)
                  .having(
                    (e) => e.message,
                    'message',
                    'Cannot negate option "--no-publishable".',
                  ),
            ),
          );
        });
      });
    });
  });
}
