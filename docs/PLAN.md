# SpecTrace — Technical Plan

**AI-assisted test intelligence for engineering teams.**
Plugs into existing CI/CD, diagnoses failed/flaky tests with evidence-backed root causes, and recommends test-suite improvements (including BDD→Jest conversion). Optional, review-only code suggestions. Provider-agnostic AI. Runs CLI-only, self-hosted, or in-pipeline.

> Status: planning document. No implementation code yet. Phases and tasks are at the end.

---

## 0. Guiding principles (read these first)

These constraints shape every decision below. When a later section seems to "cost too much" or "do too little," it is usually deferring to one of these.

1. **Useful before AI.** Parsing, normalization, flake history, and rule-based classification must deliver value with zero LLM calls. AI is an *enrichment layer*, not the product's spine.
2. **Parse first, AI second.** Deterministic extraction always runs before any model call. The AI never sees raw artifacts it doesn't need.
3. **Every AI answer cites evidence.** A diagnosis with no artifact/source citation is treated as low-confidence and flagged, not shown as fact.
4. **Code suggestions are optional, off by default, and review-only.** Never auto-applied in the MVP.
5. **Providers are interchangeable.** No vendor SDK leaks past the AI abstraction boundary.
6. **Self-hostable end to end.** A company can run the full stack internally (API, dashboard, Postgres). Hosted AI providers are acceptable for this deployment, so a local model is a *supported later option*, not an MVP requirement — but redaction and the source allowlist still apply, because even hosted calls must not leak secrets.
7. **Cost is a first-class budget, not an afterthought.** Heuristics, caching, clustering, and per-task model policy keep spend bounded and observable.
8. **Don't overengineer the MVP.** Design seams for growth (CI/CD intelligence later) but build the narrow slice well.

---

## 1. Product modes

SpecTrace is one codebase that runs in three postures. The CLI and worker share the same core analysis library; the dashboard is an optional consumer of the same data.

### 1.1 CLI-only mode
```bash
spectrace analyze ./artifacts --output report.md
```
- No dashboard, no Postgres required (uses a local SQLite store or pure stateless run).
- Parses artifacts, runs heuristics, optionally calls AI, emits a markdown/JSON report.
- This is the adoption on-ramp: a dev tries it on one failing run with zero infra.

### 1.2 Self-hosted dashboard mode
Company runs: SpecTrace API (.NET) + dashboard (Next.js) + PostgreSQL + optional object storage (artifacts) + optional Redis-backed queue worker + a configured AI provider (hosted by default; a local model endpoint is a supported later option).
- Suitable for orgs that refuse to let code/logs leave their environment.
- Same analysis core as the CLI, now persisted, trended, and searchable.

### 1.3 CI/CD integration mode
Runs inside Azure DevOps (first-class) or GitHub Actions (second). Publishes:
- markdown summary (pipeline build summary tab),
- pipeline attachment (full JSON report),
- PR comment,
- dashboard upload (if configured),
- Teams/Slack webhook (later).

The CLI *is* the CI integration — the pipeline step just invokes `spectrace analyze` with the right flags and an upload token.

---

## 2. Recommended architecture

### 2.1 High-level data flow
```
CI artifacts ─▶ Ingestion/Parsers ─▶ Normalized Failure Model
                                          │
                                          ▼
                              Heuristic classifier (no AI)
                                          │
                          ┌───────────────┴───────────────┐
                          ▼                                ▼
                 Deterministic verdict            Needs AI? (gated)
                 (cache/store)                            │
                                                          ▼
                                          Context builder (retrieval + redaction)
                                                          │
                                                          ▼
                                          AI provider router ─▶ provider
                                                          │
                                                          ▼
                                          Structured diagnosis (JSON, cited)
                                                          │
                                                          ▼
                                          Validators (anti-hallucination)
                                                          │
                                          ┌───────────────┴───────────────┐
                                          ▼                                ▼
                                  Persist + report            Optional code suggestion (if enabled)
```

### 2.2 Monorepo folder structure
A pnpm + .NET solution monorepo. TypeScript for CLI/dashboard, .NET for the API/worker/analysis core. The analysis core lives in .NET so the worker and CLI-backend share it; the CLI front-end is a thin TS wrapper that shells to or hosts the .NET core (decision below).

```
spectrace/
  apps/
    dashboard/                 # Next.js + TypeScript dashboard (the only TS in the repo)
    api/                       # .NET minimal API (read/write, auth, upload)
    worker/                    # .NET background worker (queue consumer)
    cli/                       # native .NET console CLI — references SpecTrace.Core in-process
  src/                         # .NET analysis core (the brain), referenced by api/worker/cli-host
    SpecTrace.Core/
      Ingestion/               # artifact discovery + hashing
      Parsers/
        JUnitXml/
        Trx/
        PlaywrightBdd/         # playwright-bdd JSON reporter + trace + .feature/step-def parsing
        Jest/
        Logs/                  # console/network/stack-trace parsers
      Model/                   # normalized failure model (domain types)
      Heuristics/              # rules-only classifiers (no AI)
      Retrieval/               # context builder, snippet selection, source allowlist
      Redaction/               # secret detection + scrubbing
      Ai/
        Abstraction/           # IAiProvider, IAiProviderRouter, IAiPromptRunner, ...
        Providers/             # OpenAI, Anthropic, Gemini, AzureOpenAI, Local
        Prompts/               # versioned prompt templates
        Policy/                # IAiModelPolicyService (per-task model selection)
        Validation/            # anti-hallucination validators
      Diagnosis/               # orchestrates heuristics + AI + validation
      CodeSuggestion/          # optional patch generator (gated)
      SuiteIntelligence/       # BDD→Jest analysis
      Reporting/               # markdown/JSON report writers
      Persistence/             # EF Core, repositories, migrations
      Usage/                   # IAiUsageTracker, cost tracking
  infra/
    docker/                    # Dockerfiles + compose for self-host
    db/                        # SQL migration snapshots / schema docs
  config/
    spectrace.config.example.yml
  docs/
```

**CLI architecture decision (locked).** The CLI is a **native .NET console app** (`apps/cli`) that references `SpecTrace.Core` in-process — no TypeScript wrapper, no subprocess spawning. Rationale for a .NET/Azure shop: one runtime, no Node dependency tree to audit, smallest attack surface, and idiomatic distribution via `dotnet tool install -g` or a self-contained/AOT binary. The CLI works fully offline and dashboard-free because the analysis core ships with it. Next.js is used for the **dashboard only**; it is not part of the CLI.

### 2.3 Queue / background strategy
- CLI/CI runs are **synchronous** (you want the report before the pipeline ends).
- Dashboard uploads can be **async**: API enqueues a job to Redis, the worker re-runs/links analysis and persists trends. Redis is **optional** — without it the API processes inline. Don't make Redis a hard dependency for the MVP.

### 2.4 Artifact storage strategy
- CLI mode: artifacts stay on disk; nothing is stored.
- Dashboard mode: store **derived/normalized data + small evidence pointers** in the relational DB (EF Core: PostgreSQL for dev/test, SQL Server / Azure SQL swappable for company deploy); store **large blobs** (traces, screenshots) in object storage (S3-compatible / Azure Blob) with a configurable retention policy. Default retention is short (e.g., 14 days) and configurable. Never store raw secrets; redaction runs before persistence.

---

## 3. AI strategy (the core differentiator)

### 3.1 Why this layered approach (and what we reject)

The brief lists ~10 candidate approaches. Here is the explicit reasoning, then the recommendation.

| Approach | What it buys | Why it's not the whole answer |
|---|---|---|
| **Simple log summarization** | Cheap, easy | Summary ≠ diagnosis; no root cause, no evidence, easy to hallucinate. Useful only as a *pre-step* to compress logs. |
| **Rules-only classification** | Free, deterministic, fast, no hallucination | Brittle on novel failures; can't reason across trace+log+source. Excellent as the *first pass* and to short-circuit obvious cases. |
| **LLM-only classification** | Flexible, handles novelty | Expensive at scale, hallucinates file refs, gives generic "increase timeout" answers without grounding. Bad as a standalone spine. |
| **RAG over artifacts + source** | Grounded answers, citations possible | Adds retrieval complexity; only worth it for the cases heuristics can't resolve. This is the *right tool for the hard cases*. |
| **Agentic investigation loop** | Can chase evidence iteratively | Token-hungry, slow, hard to bound cost, harder to make deterministic in CI. Defer; allow a *capped* mini-loop later. |
| **Embeddings / vector search** | Good recall over large codebases/log corpora | Operational overhead (index build, freshness). Use *only* when source retrieval is enabled and the repo is large; lexical/symbol retrieval covers most cases first. |
| **Structured JSON extraction** | Reliable downstream parsing, validatable | Not an approach by itself — it's a *requirement* of every AI call. Always on. |
| **Heuristic pre-filter before AI** | Massive cost reduction | Not a diagnosis method — it's the *gate*. Always on. |
| **Source-code-aware retrieval** | Precise fixes, fewer hallucinated paths | Requires explicit opt-in (privacy). On only when code context is enabled. |
| **Screenshot/trace-aware investigation** | Catches UI/selector/race issues invisible in logs | Multimodal cost; use selectively for UI failures with attached evidence. |

**Recommended architecture: a gated RAG pipeline with deterministic pre-filtering, structured outputs, and validation.**

```
Parse ─▶ Heuristic classify ─▶ [confident & deterministic? → done, no AI]
                                       │ else
                                       ▼
              Build minimal grounded context (retrieval + redaction)
                                       ▼
              Cheap/fast model: classify + draft cited diagnosis (JSON)
                                       ▼
              [low confidence OR high-value failure? → escalate to stronger model]
                                       ▼
              Validators (file refs exist, evidence present, not generic)
                                       ▼
              Persist verdict + evidence + usage
```

Rationale in one line: **heuristics handle the cheap majority, RAG handles the hard minority, structured JSON + validators keep it honest, and per-task model policy keeps it affordable.** We explicitly *defer* full agentic loops and vector indexing until the narrow slice proves value.

### 3.2 AI provider abstraction

No provider SDK appears outside `Ai/Providers/`. Everything upstream depends on interfaces.

```
IAiProvider              # one vendor: SendAsync(AiRequest) -> AiResponse (+ usage)
IAiProviderRouter        # picks provider+model for a given task + policy + availability/fallback
IAiPromptRunner          # renders versioned prompt, calls router, parses+validates JSON, retries
IAiUsageTracker          # records provider/model/tokens/cost/latency/promptVersion/feature
IAiModelPolicyService    # maps (task, config, risk) -> model tier; enforces cost limits
```

- **`IAiProvider`** implementations: `OpenAiProvider`, `AnthropicProvider`, `GeminiProvider`, `AzureOpenAiProvider`, and `LocalProvider` (OpenAI-compatible endpoint for Ollama/vLLM/LM Studio — built later, since hosted AI is the confirmed default). Each maps a normalized `AiRequest` to vendor calls and returns normalized usage.
- **`IAiProviderRouter`** chooses the concrete provider/model per request from `IAiModelPolicyService`, and handles fallback (e.g., provider down → secondary, or → "AI unavailable, heuristic-only result").
- **`IAiPromptRunner`** is the single choke point that *every* feature calls. It: loads the versioned prompt template, injects context, calls the router, enforces JSON schema, runs validators, retries once on schema failure, and emits usage to `IAiUsageTracker`. Centralizing this guarantees citations, redaction-checks, and tracking can't be bypassed.
- **`IAiUsageTracker`** writes one row per request (see schema): provider, model, input/output tokens, estimated cost, latency, prompt version, triggering feature, projectId, runId.
- **`IAiModelPolicyService`** resolves per-task tiers:

| Task | Default tier | Notes |
|---|---|---|
| Failure classification | cheap/fast | High volume; cheap model is fine when grounded. |
| Complex diagnosis (low-confidence/high-value) | stronger | Escalation only. |
| Code suggestions | stronger | Only when feature enabled. |
| Privacy mode (later) | local | Routes everything to `LocalProvider`. Not MVP — hosted AI is the confirmed default. |

Policy also enforces **cost limits** (per-run / per-day / per-project caps from config). When a cap is hit, the runner degrades gracefully to heuristic-only and flags it in the report rather than failing the build.

### 3.3 Token-cost strategy (concrete)

- **Parse first, AI second** — non-negotiable gate.
- **Heuristic short-circuit** — deterministic categories (e.g., known infra error string, compile error, OOM) never hit the model.
- **Never send the repo.** Source retrieval pulls only the failing test file, the symbols named in the stack trace, and N lines of surrounding context — capped per failure.
- **Local log summarization** before sending: tail + dedupe + collapse repeated lines + keep the error window. A 50k-line log becomes a few hundred relevant lines.
- **Redact before send** (secrets, tokens, connection strings, emails) — both a privacy and a token win.
- **Cluster failures with a `cause_signature` (within-run)** and diagnose the cluster once, fanning the verdict to members. This is the single biggest cost lever on large suites. **Locked design — two signatures, not one:**
  - **`cause_signature`** = `hash(error_type + normalized_message + top 3–5 project-owned stack frames)`. Deliberately **test-agnostic** so "one backend 500 broke 30 tests" collapses to a single diagnosis. Normalization strips volatile tokens before hashing: digit runs, UUIDs/GUIDs, hex addresses, timestamps, ports, temp/absolute paths, and dynamic IDs inside selectors/quoted values (`#user-4821` → `#user-N`); collapse whitespace; **do not lowercase** (identifier/selector case is signal). Stack portion keeps only project frames (framework/`node_modules`/runner frames filtered out) with line numbers dropped but file+method kept.
  - **Safety rails:** fan out only the **category + shared reasoning**, never the fix verbatim — each member keeps its own evidence, and a member whose test file/Gherkin step differs materially is ejected and diagnosed individually. Track **cluster purity** (human rejections per `cause_signature`); start strict (exact normalized match, same run) and only loosen toward similarity-threshold clustering if purity data supports it. `--no-cluster` override always available.
- **Cache by `failure_signature` (across-run)** — narrow on purpose: `hash(test_case_key + cause_signature + context_hash + prompt_version + model)`. A cached verdict is reused only for the same test, same cause, same surrounding code, same prompt/model. Clustering is broad and within-run; caching is narrow and cross-run, so the two stop competing.
- **Cap input tokens per failed test**; truncate retrieval deterministically, not randomly.
- **Cheap model for classification, stronger only on escalation, strongest only for code suggestions when enabled.**
- **Require citations** — a diagnosis that doesn't reference retrieved context is rejected, which also discourages padding context "just in case."

---

## 4. Feature areas

### A. Pipeline / test artifact ingestion
Parsers normalize everything into one **Failure Model** so downstream code is format-agnostic.

Supported inputs: JUnit XML, TRX (.NET), Playwright traces, screenshots, console logs, network logs (HAR), stack traces, source test files, recent git diff, pipeline metadata, historical results.

- **Discovery**: glob from config `artifactPaths`; hash each artifact (content hash) for caching + dedupe.
- **Normalized Failure Model** (domain type): `{ testId, displayName, suite, framework, bddFeature?, bddStep?, status, durationMs, failureMessage, stackTrace[], attachments[] (screenshot/trace/log refs), retries, sourceRefs[], historicalFlakeRate? }`.
- Parsers are independent modules with a common `IArtifactParser` contract; adding a framework = adding a parser, no core changes.

**playwright-bdd specifics (confirmed stack).** The UI tests run on [playwright-bdd](https://github.com/vitalets/playwright-bdd) — Gherkin `.feature` files compiled to Playwright specs on the Playwright runner. That means three correlated inputs:
- **Playwright JSON/blob reporter** → run results, durations, retries, attachment refs (this is the primary failure source, *not* a generic Cucumber JSON).
- **`trace.zip` + screenshots** → evidence, and because playwright-bdd wraps each Gherkin step in `test.step`, the trace gives **step-level granularity** — that's how `bddStep` gets populated and how a failure is pinned to a specific Gherkin step rather than the whole scenario.
- **`.feature` files + step-definition files** → needed for `bddFeature`/scenario text and, critically, for the Phase-9 BDD→Jest analysis (the rubric reads step text + step defs to judge whether a scenario is pure-logic vs. true-workflow).

CucumberJS / Reqnroll / SpecFlow parsers are explicitly out of MVP scope — they become additional `IArtifactParser` implementations later if needed.

### B. Failure diagnosis
For each failed test, produce: failed test name/scenario, BDD feature, BDD step (if present), failure message, stack trace, related source/test files, relevant logs, screenshot/trace evidence, historical flake rate, **likely root-cause category**, suggested fix, **confidence score**, and an **evidence list**.

Root-cause categories (enum, closed set for the classifier): `selector_issue, race_condition, timeout, test_data_cleanup, environment, api_backend_failure, auth_session, assertion_issue, network_issue, product_bug, bad_test_design, unknown`.

Flow: heuristics propose a category + confidence → if confident & deterministic, done → else RAG diagnosis fills category/fix/evidence/confidence → validators check it → persist.

Confidence is a number plus a band (low/medium/high) driven by: evidence count, whether file refs validated, heuristic/AI agreement, and historical signal. Low confidence is shown as "needs human review," never hidden — but it is **held back from PR comments** and surfaced only in the build summary and dashboard (publishing policy in §9).

### C. Optional code suggestion feature (off by default, review-only)
Config-gated. Example:
```yaml
ai:
  diagnosis:
    enabled: true
    provider: "openai"
    model: "cheap-fast-model"
  codeSuggestions:
    enabled: false
    provider: "anthropic"
    model: "stronger-model"
    maxFilesChanged: 2
    maxPatchTokens: 3000
    requireLowRiskOnly: true
```
When enabled, each suggestion includes: file path, reason, before/after explanation, suggested diff/patch, **risk level**, related evidence, confidence score, **verification command**.

**Never auto-applied.** **Refuses to patch**: high-risk production logic, security-sensitive code, DB migrations, files not present in retrieved context, weak-evidence fixes.

**Allowed safe patches** (test-level): replace `waitForTimeout` with deterministic waits, fix selectors, add missing `await`s, improve Playwright assertions, add test-data cleanup, convert pure-logic BDD scenarios into Jest tests.

Hard guardrail: the patch generator only operates on files whose **current content was retrieved into context**, and the patch is validated to apply cleanly against that exact content (see §5).

### D. Test suite intelligence (BDD→Jest)
Analyzes the suite and recommends, with reasons: keep-as-BDD, convert to Jest/unit, convert to integration/API, duplicate/overlapping, poor-ROI, high-flake/high-cost, missing lower-level coverage, and **risky tests that must not be removed**.

Decision rubric (deterministic signals + AI rationale):

- **Stay BDD** if it verifies a real user workflow, browser behavior, a cross-page journey, multi-system integration, or a critical smoke/regression path.
- **Likely → Jest/API/integration** if it only verifies pure function logic, field validation, formatting, enum/status mapping, simple permission branching, isolated component behavior, conditional rendering, or deterministic business rules.

Heuristic inputs that make this cheap: flake count/history, whether the scenario touches network/multiple pages (from trace), step text patterns, and assertion shape. The AI explains *why* and drafts the replacement; it never silently deletes the BDD.

Example output is preserved verbatim in `docs/examples/` so the report format is testable.

### E. Cost-efficient AI architecture
Covered in §3.3. Summary of always-on levers: parse-first gate, heuristic short-circuit, snippet-only retrieval, local log summarization, redaction, failure clustering, artifact-hash caching, per-failure token caps, per-task model tiers, citation requirement, and skip-AI for deterministic categories.

### F. Security & privacy
- No service-role secrets in the frontend; the dashboard talks to the API, the API holds secrets.
- **Redact before AI** — secret/PII scrubber runs on every payload (logs, diffs, source) prior to any provider call.
- **Local/self-hosted provider** supported (`LocalProvider`, OpenAI-compatible).
- **Artifact-only mode** — diagnosis with no source ever sent.
- **Source allowlist/excludelist** — code retrieval respects include/exclude globs; secrets/`.env`/keys excluded by default.
- **No full-repo upload** ever; only retrieved snippets.
- **Configurable retention**, **audit log** for every AI request (who/what/when/which provider), **RBAC** later for team dashboards.
- **Code is never sent unless explicitly enabled.** Diagnosis mode and code-suggestion mode are separate switches with separate provider/model config.

### G. UX / dashboard
Pages/panels: test-run overview, failed-tests list, flaky-tests leaderboard, diagnosis detail (root-cause category, confidence, **evidence panel** with screenshot/trace links), optional suggested-patch panel, BDD→Jest recommendations, feedback buttons (accept/reject + reason), trend charts, pipeline time/cost impact, AI usage/cost dashboard, provider/model usage breakdown, and a **config status banner** showing whether code suggestions are enabled.

UX priority: a developer under pressure should reach "what broke, why, and what to try" in one screen. Evidence is always one click away; nothing is asserted without a citation link.

### H. Configuration — `spectrace.config.yml`
One file configures: project name, CI provider, artifact paths, source include/exclude, test-framework settings, AI provider/model settings, diagnosis settings, code-suggestion toggle, redaction rules, dashboard upload settings, output format, cost limits, and confidence thresholds (including `confidence.prPublishThreshold` — the band a finding must clear to appear in a PR comment vs. build-summary/dashboard only; **defaults to `high`**). (Schema-validated; CLI fails fast with a clear message on invalid config.)

### I. Architecture
See §2 (monorepo, CLI, dashboard, API, worker, parsers, AI abstraction, retrieval, code suggestion, schema, storage, queue, provider interfaces).

### J. Data model — PostgreSQL outline
Tables and key columns (FKs implied by `*_id`):

- **projects** — `id, name, repo_url, default_branch, created_at`
- **test_runs** — `id, project_id, ci_provider, pipeline_id, branch, commit_sha, started_at, finished_at, total/passed/failed/flaky counts, status`
- **test_cases** — `id, project_id, framework, suite, display_name, bdd_feature, stable_test_key` (stable across runs)
- **test_failures** — `id, run_id, test_case_id, failure_message, stack_trace, duration_ms, retries, cause_signature` (test-agnostic, for within-run clustering) `, failure_signature` (narrow, for cross-run cache)
- **artifacts** — `id, run_id, type, storage_uri, content_hash, size_bytes, redacted (bool), created_at`
- **diagnoses** — `id, failure_id, root_cause_category, suggested_fix, confidence, confidence_band, source (heuristic|ai), prompt_version, model, created_at`
- **diagnosis_evidence** — `id, diagnosis_id, kind (log|trace|screenshot|source|history), reference, snippet, weight`
- **suggested_patches** — `id, diagnosis_id, file_path, reason, before_after, diff, risk_level, confidence, verification_command, status (proposed|accepted|rejected)`
- **flake_history** — `id, test_case_id, window, runs, fails, flake_rate, last_seen, trend`
- **test_recommendations** — `id, test_case_id, recommendation (keep_bdd|to_jest|to_integration|duplicate|low_roi|...), reason, confidence, created_at`
- **ai_requests** — `id, project_id, run_id, feature, provider, model, prompt_version, input_tokens, output_tokens, estimated_cost, latency_ms, status, created_at`
- **ai_feedback** — `id, target_type (diagnosis|patch|recommendation), target_id, verdict (accept|reject), reason, user_id, created_at`
- **provider_usage** — rollup: `id, project_id, provider, model, period, requests, input_tokens, output_tokens, cost`
- **cost_tracking** — `id, project_id, period, ai_cost, requests, cap, cap_hit (bool)`

Within-run clustering rides on `cause_signature`; cross-run caching rides on `failure_signature` (which folds in `context_hash` + `prompt_version` + `model`).

### K. Future CI/CD intelligence direction (design seams only)
Not in MVP, but the schema and ingestion leave room for: pipeline stage duration analysis, bottleneck detection, retry intelligence, PR risk scoring, affected-test selection, stage-level cost, infra-failure classification, deployment-failure diagnosis, and team/service CI health trends. The seam: `test_runs` already captures pipeline metadata; a future `pipeline_stages` table + a second analysis pass reuse the same provider abstraction and reporting layer.

---

## 5. Debugging bad outputs, hallucinations, edge cases

This is treated as a feature, not a postscript. Each risk has a concrete defense.

| Failure mode | Defense |
|---|---|
| **Hallucinated file references** | Validator checks every cited path exists in retrieved context; unknown paths → drop claim + lower confidence + flag. |
| **Incorrect root cause** | Heuristic/AI cross-check; disagreement → "needs review." Acceptance feedback trains rubric thresholds over time. |
| **Generic "increase timeout"** | Validator rejects fixes lacking specific evidence; banned-phrase + "must cite a trace/log line" rule forces grounding. |
| **Missing screenshot/trace evidence** | UI-category diagnoses *require* a trace/screenshot citation or are demoted to low confidence. |
| **Wrong BDD→Jest rec** | Conversion requires deterministic signals (no network/multi-page in trace) AND AI rationale; never auto-removes BDD. |
| **Stale source context** | Context tagged with commit SHA + content hash; mismatch with patch target → reject patch. |
| **Confusing one failure for another** | Everything keyed on `failure_signature` + `test_case` stable key; context is built per-failure, never shared loosely. |
| **Leaking secrets from logs** | Redaction runs before any provider call AND before persistence; audit log records redaction ran. |
| **Overusing expensive AI** | Heuristic gate + clustering + cache + cost caps in `IAiModelPolicyService`; cap hit → degrade to heuristic. |
| **Unsafe/risky code suggestions** | Risk classifier + allowlist of safe edit types; refuse high-risk/security/migration/weak-evidence patches. |
| **Patch doesn't match source** | Patch validated to apply cleanly against the exact retrieved file content; non-applying patch is discarded, not shown. |

Cross-cutting: **structured JSON schema on every call** (parse failures retried once then fail safe), **confidence bands surfaced in UI**, and a **"report hallucination" button** feeding `ai_feedback`.

---

## 6. Observability & iteration

Every AI call is one `ai_requests` row. The dashboard's AI section visualizes:
- prompt/version tracking, provider/model tracking, token usage, AI cost, latency,
- diagnosis accept/reject, code-suggestion accept/reject, false-positive tracking, hallucination reports,
- BDD-conversion feedback, flaky-test trend history, **pipeline time saved** (estimated from avoided manual investigation + reduced retries),
- model/provider config status, cost-limit enforcement state.

Iteration loop: feedback (`ai_feedback`) + acceptance rates per `prompt_version` → identify weak prompts/categories → revise prompt (new version) → A/B by version → measure acceptance delta. Prompt versions are immutable and tracked so quality changes are attributable.

---

## 7. Testing strategy

- **Parsers**: golden-file tests — real JUnit/TRX/Playwright fixtures → expected Failure Model. Highest-value tests in the system; they run with zero AI.
- **Heuristics**: table-driven tests over labeled failure fixtures → expected category/confidence.
- **AI layer**: provider mock implementing `IAiProvider` returning canned JSON; tests assert the runner validates, retries on bad JSON, enforces citations, tracks usage. **No live model calls in unit/CI tests.**
- **Validators**: explicit tests for each anti-hallucination rule (fake path → dropped, generic fix → rejected, non-applying patch → discarded).
- **Suite intelligence**: fixtures for each BDD→Jest signal; assert recommendation + reason.
- **Reporting**: snapshot tests on markdown/JSON output.
- **End-to-end**: CLI run against a fixture artifact bundle → deterministic report (AI mocked).
- **Eval harness** (separate from CI): a labeled set of real failures scored against accepted diagnoses to catch quality regressions when prompts/models change. Run on demand, not per-commit.

---

## 8. CLI design

```
spectrace analyze <artifactsDir> [--output report.md] [--format md|json]
                                 [--config spectrace.config.yml]
                                 [--no-ai] [--code-suggestions]
                                 [--provider openai|anthropic|gemini|azure|local]
                                 [--max-cost <usd>] [--upload]
spectrace init        # scaffold spectrace.config.yml
spectrace validate    # validate config + artifact discovery, no analysis
spectrace report      # re-render a stored JSON report to markdown
```
- Exit codes: `0` ok, `1` failures-found-and-diagnosed, `2` config/parse error. (`--fail-on` configurable so CI can choose whether diagnosis findings break the build.)
- `--no-ai` guarantees a useful heuristic-only run (proves principle #1).
- Quiet, CI-friendly default output; `--verbose` for local debugging.

---

## 9. CI/CD integration design (Azure DevOps first)

**Azure DevOps (first-class):**
- A pipeline task/step runs `spectrace analyze $(Build.ArtifactStagingDirectory) --format json --output spectrace.json`.
- Publishes markdown to the build summary, attaches `spectrace.json`, and (if a repo PR) posts a PR comment via the Azure DevOps API using a scoped token.
- Dashboard upload via `--upload` with a project token (API ingests, worker trends).

**GitHub Actions (second):** a composite action wrapping the same CLI; PR comment via the GitHub API; summary via `$GITHUB_STEP_SUMMARY`.

Both modes share one rule: **the CLI does the work, the CI wrapper only moves outputs.** This keeps integrations thin and portable, and a third CI system later is just another wrapper.

**Publishing policy by confidence (locked).** Output channels are tiered by trust, because a wrong root cause on someone's PR is the fastest way to lose the team:
- **PR comment** — **medium/high confidence only.** This is the highest-visibility, most-judged surface; a low-confidence guess here erodes adoption faster than silence. Low-confidence findings are *not* posted to PRs.
- **Build summary + dashboard** — **everything, including low-confidence "needs human review."** These are pull surfaces a developer chooses to open, so showing tentative findings there is helpful rather than noisy, and keeps low-confidence cases visible for the feedback loop (§6).
- The medium/high threshold is the `confidence.prPublishThreshold` config value (§4.H), **defaulting to `high`** for first rollout (better to under-post than burn trust early; relax to `medium` once acceptance rates justify it), so a team can tune how conservative the PR surface is. If *no* finding clears the threshold, the PR comment is suppressed entirely (or, if `--always-comment` is set, posts a one-line "N failures analyzed — see build summary" pointer instead of guesses).
- Code-suggestion patches follow the same gate **plus** their own enable flag: they never appear in a PR comment unless code suggestions are enabled *and* the suggestion is medium/high confidence and low-risk.

---

## 10. Risks & tradeoffs

- **.NET core invoked by a TS CLI** adds a packaging step (single-file/AOT binary per platform). Tradeoff accepted to avoid maintaining parsing/heuristics twice. Revisit if cross-platform binary packaging proves painful.
- **Heuristic-first** means early versions will say "unknown / needs review" more often than a pure-LLM tool. This is intentional and honest; acceptance feedback closes the gap.
- **Clustering/caching** can mask a real divergence if the signature is too coarse. Mitigate with conservative signatures (message + normalized stack) and a "diagnose individually" override.
- **Cost caps degrading to heuristic-only** can surprise users mid-run; surfaced loudly in the report and dashboard.
- **Local-model quality** varies; privacy mode trades some diagnosis quality for zero egress. Documented clearly.
- **Multimodal trace/screenshot analysis** is costly; kept selective and behind UI-category gating.

---

## 11. What NOT to build initially

- No full agentic investigation loop (cap a small escalation step at most, later).
- No vector/embeddings index until source retrieval on large repos demands it — start with lexical/symbol retrieval.
- No auto-applying patches. Review-only, always, in the MVP.
- No broader CI/CD pipeline intelligence features (stage timing, PR risk, deploy diagnosis) — seams only.
- No team RBAC/multi-tenant auth in the first dashboard cut — single-project/self-host first.
- No Teams/Slack webhooks in MVP (designed for, shipped later).
- No GitHub Actions before Azure DevOps is solid.

---

## 12. Implementation phases

Each phase: **goal · deliverables · acceptance · tests · risks · commit boundaries.** Phases are ordered so the tool is useful early and AI is additive.

> **Adoption-first sequencing note (confirmed goal: company adoption).** The strongest wedge into a skeptical team is *CLI + heuristic + AI diagnosis + an Azure DevOps PR comment* with **zero dashboard infra** — that's the "try it on one failing pipeline" moment. So pull a **minimal slice of Phase 10** (build-summary markdown + PR comment) forward to land right after Phase 5, ahead of the full dashboard (Phase 7). The dashboard is the "once they're hooked" retention piece, not the entry point. Trust features (no secret leakage, off-by-default code suggestions, honest "needs review" confidence) are weighted heavily because adoption depends on surviving a security/quality review.

### Phase 1 — Local demo app + generated artifacts
- **Goal:** a sample project that emits realistic JUnit/TRX/**playwright-bdd**/Jest artifacts (passing, failing, flaky) to develop against — including `.feature` files, step defs, the Playwright JSON reporter output, and `trace.zip`/screenshots.
- **Deliverables:** demo app, scripts to produce artifact bundles, committed fixture bundles in `docs/examples/`.
- **Acceptance:** running the demo produces all artifact types including a known-flaky and a known-selector failure.
- **Tests:** smoke script verifies expected files exist.
- **Risks:** unrealistic fixtures → weak downstream tests. Mitigate by sourcing shapes from real CI exports.
- **Commits:** `feat(demo): sample app`, `feat(demo): artifact generators`, `chore(fixtures): commit example bundles`.

### Phase 2 — CLI artifact parser
- **Goal:** parse all artifact types into the Failure Model; `spectrace analyze --no-ai` prints a normalized summary.
- **Deliverables:** parsers (JUnit, TRX, **playwright-bdd** = JSON reporter + trace + `.feature`/step-def, Jest, logs), Failure Model with `bddFeature`/`bddStep` populated from `test.step` granularity in the trace, ingestion + hashing, CLI skeleton (`analyze`, `init`, `validate`).
- **Acceptance:** golden-file parity on fixtures; CLI emits a deterministic summary with zero AI.
- **Tests:** golden-file parser tests; CLI e2e on fixtures.
- **Risks:** format variance across tool versions. Mitigate with versioned fixtures + tolerant parsing.
- **Commits:** per parser, then `feat(cli): analyze --no-ai`.

### Phase 3 — Failure diagnosis without AI
- **Goal:** heuristic classifier assigns root-cause categories + confidence with no model calls.
- **Deliverables:** `Heuristics/` rules, deterministic categories, evidence collection, markdown/JSON reporter.
- **Acceptance:** known fixtures classified correctly (selector, timeout, infra, compile, assertion) with cited evidence.
- **Tests:** table-driven heuristic tests; reporter snapshots.
- **Risks:** over-confident heuristics. Mitigate with conservative thresholds + "unknown" default.
- **Commits:** `feat(heuristics): rule engine`, `feat(report): md/json writers`.

### Phase 4 — AI provider abstraction
- **Goal:** the provider boundary + router + runner + usage tracker + policy, with a mock provider.
- **Deliverables:** `IAiProvider/Router/PromptRunner/UsageTracker/ModelPolicyService`, mock + one real provider, versioned prompt loader, JSON schema enforcement, cost caps.
- **Acceptance:** runner renders a versioned prompt, calls a provider, validates JSON, retries once, records usage; swapping providers is config-only.
- **Tests:** mock-provider unit tests for validation/retry/usage/cost-cap.
- **Risks:** leaky abstraction. Mitigate with an architecture test asserting no vendor SDK import outside `Ai/Providers/`.
- **Commits:** `feat(ai): abstraction interfaces`, `feat(ai): mock+openai provider`, `feat(ai): prompt runner + usage`.

### Phase 5 — AI diagnosis with evidence
- **Goal:** gated RAG diagnosis for cases heuristics can't resolve, fully cited and validated.
- **Deliverables:** context builder (artifact-only by default), redaction, anti-hallucination validators, escalation to stronger model, caching by signature+context hash, clustering.
- **Acceptance:** low-confidence heuristic cases get cited AI diagnoses; fabricated file refs are dropped; generic fixes rejected; clustered failures cost one call.
- **Tests:** validator unit tests; mocked-AI e2e; redaction tests.
- **Risks:** cost creep. Mitigate with caps + clustering + cache, all observable.
- **Commits:** `feat(retrieval): context builder`, `feat(ai): cited diagnosis`, `feat(ai): validators`, `feat(ai): cluster+cache`.

### Phase 6 — Optional code suggestion engine
- **Goal:** review-only patches for safe test-level issues, off by default.
- **Deliverables:** gated `CodeSuggestion/`, risk classifier, safe-edit allowlist, patch-applies-cleanly validator, verification command output, source allowlist enforcement.
- **Acceptance:** with feature on, a `waitForTimeout`/selector fix produces a clean-applying patch with risk+evidence; high-risk/migration/security/weak-evidence refused; non-applying patches discarded.
- **Tests:** patch-validation tests; refusal-path tests; redaction-before-source tests.
- **Risks:** unsafe patches. Mitigate with allowlist + refusal rules + review-only.
- **Commits:** `feat(suggest): gated engine`, `feat(suggest): risk+allowlist`, `feat(suggest): patch validator`.

### Phase 7 — Dashboard
- **Goal:** self-hosted dashboard over persisted data.
- **Deliverables:** .NET API (upload/read), EF Core schema + migrations, Next.js pages (run overview, failures, diagnosis detail + evidence, patch panel, config status banner), `--upload` from CLI.
- **Acceptance:** a CLI run uploads; dashboard renders diagnosis with clickable evidence and shows whether code suggestions are enabled.
- **Tests:** API integration tests; dashboard component tests; upload e2e.
- **Risks:** scope creep into RBAC. Mitigate by deferring auth (single-project first).
- **Commits:** `feat(api): schema+upload`, `feat(dashboard): run+diagnosis pages`, `feat(cli): --upload`.

### Phase 8 — Historical flake tracking
- **Goal:** flake rates + trends across runs.
- **Deliverables:** stable `test_case_key`, `flake_history` rollups, flaky leaderboard, trend charts, history fed back into diagnosis confidence.
- **Acceptance:** a test that intermittently fails surfaces a rising flake trend and informs diagnosis.
- **Tests:** rollup computation tests; trend snapshot tests.
- **Risks:** unstable test keys across renames. Mitigate with a tolerant key strategy + remap tooling.
- **Commits:** `feat(flake): history rollups`, `feat(dashboard): leaderboard+trends`.

### Phase 9 — BDD→Jest recommendation engine
- **Goal:** suite intelligence with reasoned conversion recommendations.
- **Deliverables:** `SuiteIntelligence/` rubric (deterministic signals + AI rationale), `test_recommendations`, dashboard recommendations panel + feedback.
- **Acceptance:** a pure-formatting BDD scenario that fails on selector churn is recommended for Jest with a reasoned, evidence-backed explanation; true-workflow BDD is kept.
- **Tests:** per-signal fixtures; recommendation snapshot; never-auto-remove assertion.
- **Risks:** wrong conversions. Mitigate by requiring deterministic signals + human review + feedback loop.
- **Commits:** `feat(suite): conversion rubric`, `feat(dashboard): recommendations`.

### Phase 10 — Azure DevOps integration
- **Goal:** first-class in-pipeline experience.
- **Deliverables:** pipeline step/template, build-summary markdown, JSON attachment, confidence-gated PR comment, `--upload` with project token.
- **Acceptance:** a failing pipeline shows a SpecTrace summary tab, attaches the report, and comments on the PR **only with medium/high-confidence findings** — low-confidence diagnoses appear in the build summary/dashboard but never in the PR comment.
- **Tests:** integration test against ADO APIs (sandbox); CLI exit-code behavior tests; **PR-publishing gate test** (low-confidence finding is excluded from the PR comment, present in the summary).
- **Risks:** token scoping/permissions. Mitigate with least-privilege tokens + docs.
- **Commits:** `feat(ci): ado step`, `feat(ci): pr comment + summary`.

### Phase 11 — Feedback / monitoring loop
- **Goal:** close the iteration loop with full AI observability.
- **Deliverables:** `ai_feedback` capture (accept/reject/hallucination), AI usage/cost dashboard, provider/model breakdown, prompt-version A/B, pipeline-time-saved metric, cost-cap enforcement UI.
- **Acceptance:** acceptance rates per prompt version are visible; a hallucination report is recorded; cost caps show enforcement state.
- **Tests:** feedback API tests; usage rollup tests; metrics snapshot.
- **Risks:** vanity metrics. Mitigate by anchoring on acceptance rate + cost per accepted diagnosis.
- **Commits:** `feat(feedback): capture`, `feat(dashboard): ai usage+cost`, `feat(ai): prompt A/B`.

### Phase 12 — Company-ready self-hosted package
- **Goal:** one-command self-host of the full stack against a hosted AI provider; local-model support is an optional stretch.
- **Deliverables:** Docker Compose (API + dashboard + Postgres + optional Redis + optional object storage), provider config (hosted default), retention + audit log, `spectrace.config.example.yml`, install/runbook docs. *Stretch:* `LocalProvider` wiring + egress-free mode for a future privacy-sensitive customer.
- **Acceptance:** a fresh machine runs the full stack via compose against a hosted provider; redaction + retention + audit verified. *Stretch acceptance:* local-model mode routes all AI to a local endpoint with zero external egress.
- **Tests:** compose smoke test; retention job test; redaction-on-egress test. *Stretch:* egress test in local-model mode.
- **Risks:** environment drift. Mitigate with pinned images + a documented support matrix.
- **Commits:** `feat(infra): compose`, `feat(infra): privacy mode`, `docs(deploy): runbook`.

---

## 13. Summary

SpecTrace earns trust by being useful with **zero AI** (deterministic parsing, heuristics, flake history), then layers a **gated, cited, validated** AI pipeline on top — cheap models for the common cases, stronger models only on escalation or for optional review-only code suggestions. Hosted AI is the confirmed default, with a local-model path kept as a clean later option behind the provider abstraction. The abstraction keeps vendors swappable; the cost/observability layer keeps spend bounded and quality measurable; and the phased plan (CLI + Azure DevOps PR comment first, dashboard second) ships something a team can actually adopt at every step rather than a flashy demo that can't go to production.
