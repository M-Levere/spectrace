# TASKS.md — SpecTrace

Work order. One phase at a time; don't start a phase until the prior phase's **acceptance** passes. Full detail (deliverables/tests/risks/commits) per phase is in `docs/PLAN.md §12`. Check items off as you go.

> **Sequencing note:** after Phase 5, pull a minimal GitHub Actions slice forward (step-summary report + confidence-gated PR comment) *before* the full dashboard in Phase 7. Marked `[CI-EARLY]` below.

---

## Phase 0 — Repo bootstrap (you are here)
- [ ] Confirm folder skeleton matches `docs/PLAN.md §2.2`.
- [ ] Target .NET 10 (LTS). .NET solution: `SpecTrace.Core` (library) referenced by `apps/cli`, `apps/api`, `apps/worker`. CLI is a native .NET console app (no TypeScript, no spawn).
- [ ] Next.js app in `apps/dashboard` (the only TS in the repo); pnpm scoped to it.
- [ ] Add base test projects (xUnit for .NET, vitest for the dashboard) so every later phase has a home for tests.
- [ ] EF Core wired in `Persistence/` against PostgreSQL (Docker postgres). Single provider.
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

## [CI-EARLY] Minimal GitHub Actions slice (after Phase 5, before Phase 7)
- [ ] A GitHub Actions workflow runs the CLI on a PR; writes the markdown report to `$GITHUB_STEP_SUMMARY` and uploads the JSON as a build artifact.
- [ ] Confidence-gated PR comment (medium/high only; `prPublishThreshold` default `high`); suppress if nothing clears.
- [ ] Collection step uses `if: always()` so a failed test job still hands over the result files.
- Acceptance: a PR with a failing test shows the SpecTrace summary + a PR comment with high-confidence findings only.
- Commits: `feat(ci): gha summary`, `feat(ci): gated pr comment`.

## Phase 6 — Optional code suggestion engine
- [ ] Gated `CodeSuggestion/`: risk classifier, safe-edit allowlist, patch-applies-cleanly validator, verification command, source allowlist.
- Acceptance: with feature on, a `waitForTimeout`/selector fix → clean patch w/ risk+evidence; high-risk/migration/security/weak-evidence refused; non-applying discarded.
- Tests: patch-validation, refusal-path, redaction-before-source.
- Commits: `feat(suggest): gated engine`, `feat(suggest): risk+allowlist`, `feat(suggest): patch validator`.

## Phase 7 — Dashboard
- [ ] `apps/api` upload/read + EF Core schema/migrations (`Persistence/`, PostgreSQL); `apps/dashboard` pages (run overview, failures, diagnosis detail + evidence, patch panel, config-status banner); `--upload`.
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

## Phase 10 — CI integration (full)
- [ ] Harden the [CI-EARLY] slice into a reusable **GitHub Actions** composite action: PR-comment lifecycle (update existing comment, not spam), `--upload` token, exit codes, `if: always()` collection.
- [ ] (Optional) Azure DevOps equivalent if you want it for your own pipelines.
- Acceptance: a public repo shows the full GitHub Actions experience; PR comment gated to medium/high; low-confidence in summary/dashboard only.
- Commits: `feat(ci): gha action`, `feat(ci): pr comment lifecycle`.

## Phase 11 — Feedback / monitoring loop
- [ ] `ai_feedback` capture (accept/reject/hallucination); AI usage/cost dashboard; provider/model breakdown; prompt-version A/B; pipeline-time-saved; cost-cap UI.
- Acceptance: acceptance rates per prompt version visible; hallucination report recorded; cost caps show enforcement.
- Commits: `feat(feedback): capture`, `feat(dashboard): ai usage+cost`, `feat(ai): prompt A/B`.

## Phase 12 — Run-it-yourself package (lightweight)
- [ ] Docker Compose (api + dashboard + Postgres + optional Redis/MinIO); `spectrace.config.example.yml`; a short "run locally" section in the README.
- Acceptance: `docker compose up` brings up the full stack on a fresh machine and the dashboard loads.
- Commits: `feat(infra): compose`, `docs: run-locally`.
- Note: no enterprise runbook / audit / retention hardening needed for the portfolio — keep it simple.

## Phase 13 — Portfolio polish (the part that gets you hired)
- [ ] **README**: problem statement, what it does, an architecture diagram, a labeled screenshot or demo GIF, quickstart, and tech highlights.
- [ ] **Demo**: a short recorded run (CLI diagnosing a failure → dashboard view), or a hosted demo dashboard with seeded sample data.
- [ ] Make the public repo presentable: clean commit history, the planning docs (`PLAN.md`, `CONTRACTS.md`) linked from the README to show design thinking, a license, badges.
- Acceptance: a stranger can understand what it is and see it work in under two minutes without running anything.
- Commits: `docs: readme + architecture`, `docs: demo`.

> **Scope note:** Phases 1–7 already make a complete, demoable story (parse → diagnose → dashboard). Phases 8–11 add depth if you have time; 12–13 are about presentation. A polished 1–7 + 13 beats a half-finished 1–11.
