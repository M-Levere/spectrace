---
name: gen-fixtures
description: Generate fake/sample test-artifact bundles for SpecTrace development, tests, and the demo. Use when you need playwright-bdd, Jest, JUnit XML, or .NET TRX artifacts (passing, failing, flaky, selector-failure) without a real pipeline — including the Phase 1 demo and golden-file parser fixtures.
---

# Generate sample artifacts

There's no access to the real company pipeline, so the demo and tests run on generated artifacts. Make them realistic enough to exercise parsers and heuristics.

## What to produce
For each framework, generate bundles covering these outcomes:
- **passing** (baseline),
- **failing — selector issue** (playwright-bdd; element not found),
- **failing — timeout / race condition**,
- **failing — assertion mismatch**,
- **flaky** (same test passes and fails across repeated runs — needed for flake history).

Per playwright-bdd bundle include: Playwright JSON reporter output, a `trace.zip`, screenshots, and the `.feature` + step-def files. For .NET include a real-shaped `.trx`. For Jest include its JSON reporter output. For JUnit include valid JUnit XML.

## Rules
- Shapes must match what the real tools emit (so parsers built against fixtures work on real data). Base structures on actual tool output, not guesses.
- Commit bundles under `docs/examples/<framework>/<scenario>/`.
- Keep at least one **known-flaky** and one **known-selector-failure** bundle — heuristics and the demo depend on them.
- No real secrets or company data in fixtures.

## Done when
- Running the generator produces all frameworks × scenarios, committed under `docs/examples/`.
- A smoke script verifies expected files exist.
- Commit: `chore(fixtures): <framework> sample artifacts` (or `feat(demo): artifact generators`).
