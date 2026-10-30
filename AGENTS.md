# Agent rules — gntrees-os

## Documentation

- `AGENTS.md` is the **only** Markdown file in this repository.
- Do not add `PLAN.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `README.md`, or any other
  roadmap/plan document. Roadmaps change; they are not persisted as files.
- Durable technical notes, when needed, are plain text under `docs/`.
- Do not create `.agents/skills/` in this repository. The placement rule lives in
  `docs/code-placement.txt`.

## Code placement

Before creating, moving, renaming, or reorganizing any file or folder, follow the
kind + domain rule in **`docs/code-placement.txt`**. That file is the authoritative
project placement note, including the kind/domain vocabulary for this repo and the
recorded exceptions. Record any new exception there instead of bending the layout
silently.

## Build rules

- `just` is the only task runner.
- Never build inside the working tree: it is on NTFS. All artifacts live under
  `~/.cache/gntrees-os` (override with `GNTREES_BUILD_DIR`).
- Do not run long builds, pull container images, or fetch sources unless asked.
- COSMIC components are pinned in `config/versions.lock`; do not use floating
  branches.
