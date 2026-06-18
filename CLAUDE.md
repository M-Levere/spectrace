# CLAUDE.md — SpecTrace

> Operating brief for Claude Code. Read this first, then `docs/PLAN.md` (full spec) and `TASKS.md` (work order). `CONTRACTS.md` holds the stable interface/shape contracts — treat those as fixed unless a change is proposed and agreed.

## What this is

SpecTrace is an AI-assisted test-intelligence tool. It ingests CI test artifacts (playwright-bdd, Jest, JUnit XML, .NET TRX), diagnoses failed/flaky tests with **evidence-backed** root causes, and recommends test-suite improvements (incl. BDD→Jest). Optional, review-only code suggestions. Provider-agnostic AI. Runs CLI-only, self-hosted, or in-pipeline.

## Locked decisions (do not re-litigate)

- **Hosted AI is the default.** Local model (`LocalProvider`) is a clean later option behind the abstraction — not MVP. Redaction + source allowlist still apply to hosted calls.
- **UI tests are playwright-bdd (Gherkin).** Parse the Playwright JSON reporter + `trace.zip`/screenshots + `.feature`/step-def files. `bddStep` comes from `test.step` granularity in the trace. No CucumberJS/Reqnroll/SpecFlow parsers in MVP.
- **Adoption-first sequencing.** The wedge is CLI + heuristic + AI diagnosis + an **Azure DevOps PR comment**, zero dashboard infra. Pull the minimal ADO slice (build summary + PR comment) forward to right after Phase 5, ahead of the dashboard (Phase 7).
- **Two clustering signatures.** `cause_signature` (test-agnostic, within-run clustering) and `failure_signature` (narrow, cross-run cache). See CONTRACTS.md.
- **Code suggestions: OFF by default, review-only, never auto-applied.** Refuse high-risk/security/migration/weak-evidence/uncontextualized patches.
- **`confidence.prPublishThreshold` defaults to `high`.** PR comments carry medium/high only; low-confidence goes to build summary + dashboard only.
- **CLI is native .NET, no TypeScript wrapper.** `apps/cli` is a .NET console app that references `SpecTrace.Core` directly (in-process, no spawning). Ships as a `dotnet tool` or self-contained binary. Must work offline / dashboard-free. The Next.js stack is for the dashboard only.
- **DB via EF Core, provider-swappable.** Develop and test on **PostgreSQL** (easy local, no licensing). Ship so a company can point at **SQL Server / Azure SQL** by changing the provider + connection string. Keep the `DbContext` provider-agnostic — avoid Postgres-only features (jsonb tricks, arrays, `ON CONFLICT`) so both stay possible. Maintain migrations per provider.

## Principles (every decision defers to these)

1. Useful before AI — parsing/heuristics/flake history deliver value with zero LLM calls.
2. Parse first, AI second — deterministic extraction always runs before any model call.
3. Every AI answer cites evidence from artifacts/source, or it's low-confidence + flagged.
4. Code suggestions optional, off by default, review-only.
5. Providers interchangeable — **no vendor SDK outside `src/SpecTrace.Core/Ai/Providers/`**.
6. Self-hostable end to end (hosted AI default).
7. Cost is a budget — heuristic gate, clustering, cache, per-task model policy, observable spend.
8. Don't overengineer the MVP — build seams for CI/CD intelligence later, build the narrow slice well.

## Stack

- Frontend: Next.js + TypeScript (`apps/dashboard`)
- Runtime: .NET 10 (LTS) / C# 14, EF Core 10
- API/worker/core: .NET (`apps/api`, `apps/worker`, `src/SpecTrace.Core`)
- CLI: native .NET console app (`apps/cli`) referencing `SpecTrace.Core` directly — no Node, no spawn
- DB: EF Core. PostgreSQL for dev/test; SQL Server / Azure SQL as a config-swappable provider for company deployment
- Optional: Redis (queue), S3/Azure Blob (artifacts)
- CI: Azure DevOps first (test on your own ADO org), GitHub Actions second

## Working agreement

- Work **one phase at a time**, in `TASKS.md` order. Don't start a phase until the prior phase's acceptance criteria pass (the one exception is the adoption-first ADO slice, called out in TASKS).
- Every AI call goes through `IAiPromptRunner` — never call a provider directly from a feature.
- Every phase ships with its tests (see PLAN §7). AI tests use the mock provider; **no live model calls in unit/CI tests.**
- Use the commit boundaries listed per phase. Conventional commits (`feat(...)`, `fix(...)`, `test(...)`, `docs(...)`, `chore(...)`).
- Keep changes scoped to the current phase. If you find you need something from a later phase, note it in TASKS rather than building ahead.
- Before any architectural deviation from PLAN/CONTRACTS, stop and propose it — don't silently diverge.
- At the end of each phase, STOP: summarize what changed and confirm acceptance criteria pass. Do not start the next phase, and do not commit — wait for me to review and commit.

## Definition of done (per phase)

- Acceptance criteria in `TASKS.md` met and demonstrated.
- Tests written and passing; deterministic (no network/model dependence in CI).
- No vendor SDK leaked past the AI provider boundary (architecture test enforces this from Phase 4).
- Docs/examples updated where the phase changes output format.

## Do NOT (in MVP)

- Auto-apply code patches. Review-only, always.
- Build a full agentic investigation loop, a vector/embeddings index, team RBAC, or Teams/Slack webhooks.
- Send the repo to a model — only retrieved, redacted snippets, capped per failure.
- Invent file paths. Cite only paths present in retrieved context; validators must drop the rest.
- Build broader CI/CD intelligence (stage timing, PR risk, deploy diagnosis) — seams only.
