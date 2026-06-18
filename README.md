# SpecTrace

AI-assisted test-intelligence for engineering teams. Ingests CI test artifacts (playwright-bdd, Jest, JUnit XML, .NET TRX), diagnoses failed/flaky tests with evidence-backed root causes, and recommends test-suite improvements (incl. BDD→Jest). Optional, review-only code suggestions. Provider-agnostic AI. Runs CLI-only, self-hosted, or in-pipeline.

> **Status: planning / Phase 0.** No implementation yet. This repo is scaffolding + the technical plan.

## Where things live
- `docs/PLAN.md` — full technical plan (architecture, AI strategy, schema, phases). **Start here.**
- `CLAUDE.md` — operating brief + locked decisions for Claude Code.
- `CONTRACTS.md` — stable shapes/interfaces (Failure Model, AI abstraction, signatures, enums).
- `TASKS.md` — phase-by-phase work order with acceptance criteria.
- `spectrace.config.example.yml` — canonical config.
- `src/SpecTrace.Core/` — the .NET analysis core (the brain), referenced by api/worker/cli-host.
- `apps/` — `dashboard` (Next.js), `api` + `worker` + `cli` (.NET). The CLI is native .NET and references `SpecTrace.Core` directly.
- `infra/` — Docker + DB; `docs/examples/` — fixture artifact bundles.

## Working on this with Claude Code
1. Read `CLAUDE.md`, then `docs/PLAN.md`, then `TASKS.md`.
2. Work one phase at a time, in order. Don't start a phase until the prior phase's acceptance passes.
3. Tests ship with each phase; AI tests use the mock provider (no live model calls in CI).
