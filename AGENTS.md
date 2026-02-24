# Agent Guidelines and Instructions

This repository contains specific guidelines and conventions that AI agents and tools must follow when contributing to the codebase.

## Mise Tasks

When defining tasks for `mise`:
- **Single-line commands**: It is acceptable to inline these directly in `mise.toml` using the `[tasks.name]` `run` attribute.
- **Multi-line scripts**: Do **NOT** inline multi-line bash scripts within the `mise.toml` configuration. Instead, you must create a file task in the `.mise-tasks` directory (e.g., `.mise-tasks/category/task-name`) and write the full bash script there.

For example, to create a task `generate:proto` that executes a loop, create an executable file at `.mise-tasks/generate/proto`.
