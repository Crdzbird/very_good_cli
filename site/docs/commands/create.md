---
sidebar_position: 0
---

# Create 🚀

Create a new Very Good project from a template with `very_good create`. Each
template type has a corresponding subcommand.

## Usage

```sh
Creates a new Very Good project in the specified directory.

Usage: very_good create <subcommand> <project-name> [arguments]
-h, --help    Print this usage information.

Available subcommands:
  app_ui_package    Generate a Very Good App UI package.
  dart_cli          Generate a Very Good Dart CLI application.
  dart_package      Generate a Very Good Dart package.
  docs_site         Generate a Very Good documentation site.
  flame_game        Generate a Very Good Flame game.
  flutter_app       Generate a Very Good Flutter application.
  flutter_package   Generate a Very Good Flutter package.
  flutter_plugin    Generate a Very Good Flutter plugin.

Run "very_good help" to see global options.
```

:::tip
Use `-o` or `--output-directory` to specify a custom output directory for the
generated project.
:::

## Creating in the current directory

Instead of specifying a project name, you can pass `.` to create the project
in your current directory. Very Good CLI derives the project name from your
current directory's basename. This works with every template subcommand.

For example, if your working directory is `/home/user/my_flutter_app`, the
following command creates a Flutter app named `my_flutter_app` in place:

```sh
# Create a Flutter app named after the current directory
very_good create flutter_app .
```

You can combine `.` with any other supported flags for that template:

```sh
# Create a Flutter app with a custom org name
very_good create flutter_app . --org "com.company"

# Create a Flutter app with a description
very_good create flutter_app . --desc "My production Flutter app"

# Create a publishable Dart package
very_good create dart_package . --desc "My Dart package" --publishable

# Create a Flutter plugin that supports specific platforms
very_good create flutter_plugin . --desc "My plugin" --platforms android,ios,web
```

:::note
You cannot combine `.` with `--output-directory`. Very Good CLI will exit with
an error if you specify both.
:::

## Available templates

Each subcommand maps to a specific project template. For detailed usage options
and examples, see the individual template pages:

- [Flutter Starter App](../templates/core.md) — `flutter_app`
- [Dart CLI](../templates/dart_cli.md) — `dart_cli`
- [Dart Package](../templates/dart_pkg.md) — `dart_package`
- [Flutter Package](../templates/flutter_pkg.md) — `flutter_package`
- [Flutter Federated Plugin](../templates/federated_plugin.md) — `flutter_plugin`
- [Flame Game](../templates/flame_game.md) — `flame_game`
- [App UI Package](../templates/app_ui_package.md) — `app_ui_package`
- [Docs Site](../templates/docs_site.md) — `docs_site`

## Workspaces

Generate any project pre-configured as a member of a
[pub workspace](https://dart.dev/tools/pub/workspaces) with the opt-in
`--workspace` flag, available on every template subcommand (off by default).

The flag is forwarded to the template as the `workspace` variable, so the
generated project ships with the workspace-member configuration
(`resolution: workspace`) out of the box — compatible with plain pub workspaces
and monorepo tools built on top of them (e.g. melos):

```sh
very_good create dart_package my_package -o packages --workspace
very_good create flutter_app  my_app     -o apps     --workspace
```

:::note
The flag is forwarded to the template as the `workspace` variable and takes
effect once the bundled templates support it (see
[very_good_templates](https://github.com/VeryGoodOpenSource/very_good_templates));
with older templates it is accepted but has no effect on the generated files.
:::

## Monorepos

When a project is generated inside an existing git repository (e.g. a
monorepo), its GitHub metadata is automatically integrated at the repository
root — where GitHub actually reads it — resolving conflicts with any existing
files:

- Workflows are renamed after the project (`main.yaml` becomes
  `<project_name>.yaml`, with `_1`, `_2`… suffixes on residual conflicts) and
  scoped to the package directory via path filters and `working_directory`
  inputs.
- `dependabot.yaml` keeps its existing entries and gains new ones pointing at
  the package directory (`enable-beta-ecosystems` is enabled when required).
- `cspell.json` merges the Very Good dictionaries and the project name into
  the existing configuration.
- `PULL_REQUEST_TEMPLATE.md` and `ISSUE_TEMPLATE/*` are overwritten — review
  the diff and commit or revert.

Nothing happens when the project is generated outside a git repository or is
the repository root itself.

