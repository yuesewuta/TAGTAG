# Issue tracker: Local Markdown

Issues and specs for this repo live as Markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- Feature specification: `.scratch/<feature-slug>/spec.md`
- One implementation ticket per file: `.scratch/<feature-slug>/issues/<NN>-<slug>.md`
- Ticket numbering starts from `01`
- Comments are appended under a `## Comments` heading

## Publishing

When publishing an issue or specification, create the corresponding file under `.scratch/<feature-slug>/`.

## Fetching

Read the referenced issue or specification directly from its local path.

## Wayfinding

- Map: `.scratch/<effort>/map.md`
- Child ticket: `.scratch/<effort>/issues/<NN>-<slug>.md`
- Ticket types: `research`, `prototype`, `grilling`, or `task`
- Ticket states: `claimed` or `resolved`
- Dependencies use `Blocked by: NN, NN`
