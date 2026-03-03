# Agent Guidelines and Instructions

This repository contains specific guidelines and conventions that AI agents and tools must follow when contributing to the codebase.

## Mise Tasks

When defining tasks for `mise`:
- **Single-line commands**: It is acceptable to inline these directly in `mise.toml` using the `[tasks.name]` `run` attribute.
- **Multi-line scripts**: Do **NOT** inline multi-line scripts within the `mise.toml` configuration. Instead, you must create a file task in the `.mise-tasks` directory (e.g., `.mise-tasks/category/task-name`) and write the full script there.
- **Language preference**: Always prefer using `bun` (`#!/usr/bin/env bun`) when creating file tasks instead of `bash` or `python`.
- **Comments**: When using `bun` for file tasks, include MISE attributes as comments starting with `//MISE` (**CRITICAL**: there must be NO space between `//` and `MISE`, or mise will ignore it!). For example, `//MISE description="Task description"`. You should also include `//USAGE` or `// USAGE` comments to provide examples if appropriate.

For example, to create a task `generate:proto` that executes a loop, create an executable bun script at `.mise-tasks/generate/proto`.
