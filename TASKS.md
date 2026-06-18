# TASKS.md — SpecTrace

Work order. One phase at a time; don't start a phase until the prior phase's **acceptance** passes. Full detail (deliverables/tests/risks/commits) per phase is in `docs/PLAN.md §12`. Check items off as you go.

> **Adoption-first exception:** after Phase 5, pull a minimal ADO slice forward (build-summary markdown + confidence-gated PR comment) *before* building the full dashboard in Phase 7. Marked `[ADO-EARLY]` below.

---

## Phase 0 — Repo bootstrap (you are here)
- [ ] Confirm folder skeleton matches `docs/PLAN.md §2.2`.
- [ ] Target .NET 10 (LTS). .NET solution: `SpecTrace.Core` (library) referenced by `apps/cli`, `apps/api`, `apps/worker`. CLI is a native .NET console app (no TypeScript, no spawn).
- [ ] Next.js app in `apps/dashboard` (the only TS in the repo); pnpm scoped to it.
- [ ] Add base test projects (xUnit for .NET, vitest for the dashboard) so every later phase has a home for tests.
- [ ] EF Core wired in `Persistence/` against PostgreSQL for dev (Docker postgres); keep `DbContext` provider-agnostic for a later SQL Server swap.
- [ ] CI: a lint+test workflow on push (no analysis logic yet).
- Acceptance: `dotnet build` + `dotnet test` + dashboard build all green; `dotnet run --project apps/cli` prints help.
- Commits: `chore(repo): solution + cli + core`, `chore(db): ef core + postgres dev`, `chore(ci): lint+test workflow`.

## Phase 1 — Local demo app + generated artifacts
- [ ] Sample playwright-bdd project with `.feature` files + step defs, plus Jest + a .NET (TRX) sample.
- [ ] Scripts to produce artifact bundles: passing, failing, **known-flaky**, **known-selector failure**.
- [ ] Ensure outputs include Playwright JSON reporter, `trace.zip`, screenshots, `.feature`/step-defs.
- [ ] Commit fixture bundles to `docs/examples/`.
- Acceptance: running the demo produces all artifact types incl. a known-flaky and a known-selector failure.
- Tests: smoke script verifies expected files exist.
- Commits: `feat(demo): sample app`, `feat(demo): artifact generators`, `chore(fixtures): example bundles`.

## Phase 2 — CLI artifact parser
- [ ] `Model/` — Failure Model (see CONTRACTS.md).
- [ ] `Ingestion/` — glob discovery + content hashing.
- [ ] Parsers: JUnitXml, Trx, PlaywrightBdd (JSON reporter + trace + `.feature`/step-def, `bddStep` from `test.step`), Jest, Logs.
- [ ] Native .NET CLI (`apps/cli`) skeleton: `analyze`, `init`, `validate`. `spectrace analyze ./artifacts --no-ai` prints a normalized summary, no model calls.
- Acceptance: golden-file parity on fixtures; deterministic summary with zero AI.
- Tests: golden-file parser tests; CLI e2e on fixtures.
- Commits: per parser, then `feat(cli): analyze --no-ai`.

## Phase 3 — Failure diagnosis without AI
- [ ] `Heuristics/` rule engine → root-cause category + confidence, no model calls.
- [ ] Evidence collection; `Reporting/` markdown + JSON writers.
- Acceptance: selector/timeout/infra/compile/assertion fixtures classified correctly with cited evidence.
- Tests: table-driven heuristic tests; reporter snapshots.
- Commits: `feat(heuristics): rule engine`, `feat(report): md/json writers`.

## Phase 4 — AI provider abstraction
- [ ] `Ai/Abstraction/` interfaces (CONTRACTS.md), mock provider + one real (OpenAI).
- [ ] `Ai/Prompts/` versioned loader; JSON schema enforcement; retry-once; cost caps in policy.
- [ ] `Usage/` `IAiUsageTracker`.
- [ ] **Architecture test**: no vendor SDK import outside `Ai/Providers/`.
- Acceptance: runner renders versioned prompt → provider → validates JSON → retries once → records usage; provider swap is config-only.
- Tests: mock-provider unit tests (validation/retry/usage/cost-cap) + architecture test.
- Commits: `feat(ai): abstraction`, `feat(ai): mock+openai`, `feat(ai): prompt runner + usage`.

## Phase 5 — AI diagnosis with evidence
- [ ] `Retrieval/` context builder (artifact-only by default) + `Redaction/`.
- [ ] `Ai/Validation/` anti-hallucination validators (file-ref existence, evidence-required, no generic fix, patch-applies).
- [ ] Escalation to stronger model on low confidence; clustering (`cause_signature`) + cache (`failure_signature`).
- Acceptance: low-confidence heuristic cases get cited AI diagnoses; fabricated refs dropped; generic fixes rejected; clustered failures cost one call.
- Tests: validator units; mocked-AI e2e; redaction tests.
- Commits: `feat(retrieval): context builder`, `feat(ai): cited diagnosis`, `feat(ai): validators`, `feat(ai): cluster+cache`.

## [ADO-EARLY] Minimal Azure DevOps wedge (after Phase 5, before Phase 7)
- [ ] Pipeline step runs CLI; publishes build-summary markdown + attaches JSON. Test on your OWN Azure DevOps org first.
- [ ] Confidence-gated PR comment (medium/high only; `prPublishThreshold` default `high`); suppress if nothing clears.
- Acceptance: failing pipeline shows summary + PR comment with high-confidence findings only.
- Commits: `feat(ci): ado summary`, `feat(ci): gated pr comment`.

## Phase 6 — Optional code suggestion engine
- [ ] Gated `CodeSuggestion/`: risk classifier, safe-edit allowlist, patch-applies-cleanly validator, verification command, source allowlist.
- Acceptance: with feature on, a `waitForTimeout`/selector fix → clean patch w/ risk+evidence; high-risk/migration/security/weak-evidence refused; non-applying discarded.
- Tests: patch-validation, refusal-path, redaction-before-source.
- Commits: `feat(suggest): gated engine`, `feat(suggest): risk+allowlist`, `feat(suggest): patch validator`.

## Phase 7 — Dashboard
- [ ] `apps/api` upload/read + EF Core schema/migrations (`Persistence/`, Postgres dev; SQL Server provider swappable); `apps/dashboard` pages (run overview, failures, diagnosis detail + evidence, patch panel, config-status banner); `--upload`.
- Acceptance: CLI run uploads; dashboard renders diagnosis w/ clickable evidence + code-suggestion enabled/disabled status.
- Tests: API integration, dashboard component, upload e2e.
- Commits: `feat(api): schema+upload`, `feat(dashboard): run+diagnosis`, `feat(cli): --upload`.

## Phase 8 — Historical flake tracking
- [ ] Stable `test_case_key`, `flake_history` rollups, leaderboard, trend charts; history feeds diagnosis confidence.
- Acceptance: intermittent test surfaces a rising flake trend and informs diagnosis.
- Commits: `feat(flake): history rollups`, `feat(dashboard): leaderboard+trends`.

## Phase 9 — BDD→Jest recommendation engine
- [ ] `SuiteIntelligence/` rubric (deterministic signals + AI rationale); `test_recommendations`; dashboard panel + feedback.
- Acceptance: pure-formatting BDD failing on selector churn → Jest recommendation w/ reasons; true-workflow BDD kept; never auto-removes BDD.
- Commits: `feat(suite): conversion rubric`, `feat(dashboard): recommendations`.

## Phase 10 — Azure DevOps integration (full)
- [ ] Harden the [ADO-EARLY] slice: templates, PR-comment lifecycle, `--upload` token, exit codes.
- Acceptance: full ADO experience; PR comment gated to medium/high; low-confidence in summary/dashboard only.
- Commits: `feat(ci): ado step`, `feat(ci): pr comment + summary`.

## Phase 11 — Feedback / monitoring loop
- [ ] `ai_feedback` capture (accept/reject/hallucination); AI usage/cost dashboard; provider/model breakdown; prompt-version A/B; pipeline-time-saved; cost-cap UI.
- Acceptance: acceptance rates per prompt version visible; hallucination report recorded; cost caps show enforcement.
- Commits: `feat(feedback): capture`, `feat(dashboard): ai usage+cost`, `feat(ai): prompt A/B`.

## Phase 12 — Company-ready self-hosted package
- [ ] Docker Compose (api + dashboard + Postgres + optional Redis + optional object storage); hosted-provider config; retention + audit log; `spectrace.config.example.yml`; runbook. *Stretch:* `LocalProvider` + egress-free mode.
- Acceptance: fresh machine runs full stack via compose against hosted provider; redaction + retention + audit verified.
- Commits: `feat(infra): compose`, `docs(deploy): runbook`.
