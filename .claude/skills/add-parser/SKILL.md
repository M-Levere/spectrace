---
name: add-parser
description: Add a new test-artifact parser to SpecTrace.Core. Use when adding or changing support for a test format (JUnit XML, .NET TRX, playwright-bdd, Jest, console/network/stack-trace logs) — anything that turns a raw artifact into the normalized Failure Model.
---

# Add an artifact parser

Parsers are the foundation; everything downstream depends on the Failure Model, so get this right and test it hard. No AI here — pure deterministic parsing.

## Rules
- Implement `IArtifactParser` (`CanParse`, `Parse -> Failure[]`). Nothing format-specific may leak past the Failure Model.
- Conform exactly to the Failure Model in `CONTRACTS.md`. If a field isn't available in this format, leave it null — don't invent it.
- For playwright-bdd specifically: read the Playwright JSON reporter (not generic Cucumber JSON), plus `trace.zip`/screenshots, plus `.feature`/step-def files. Populate `bddStep` from the `test.step` granularity in the trace.
- One parser per format under `src/SpecTrace.Core/Parsers/<Format>/`. Adding a format must not require core changes.

## Workflow (test-first)
1. Add/locate a real fixture artifact in `docs/examples/` (use the `gen-fixtures` skill if none exists).
2. Write the golden-file test FIRST: fixture in → expected Failure Model out. These are the highest-value tests in the repo.
3. Implement the parser until the golden test passes.
4. Add edge-case fixtures: empty result, partial/malformed XML, retries, flaky, missing attachments.
5. Keep parsing tolerant of tool-version variance; prefer "field absent" over throwing.

## Done when
- Golden-file parity on all fixtures, deterministic, zero AI.
- `spectrace analyze ./artifacts --no-ai` includes failures from this format in the summary.
- Commit: `feat(parsers): <format> parser` (+ `chore(fixtures): <format> bundle` if new fixtures).
