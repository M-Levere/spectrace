# CONTRACTS.md — SpecTrace

Stable contracts. Design-level, not implementation — but treat the **shapes, names, and responsibilities** as fixed unless a change is proposed and agreed. Full rationale lives in `docs/PLAN.md`.

## Normalized Failure Model (the spine)
Everything downstream depends on this; parsers produce it, nothing else.

```
Failure {
  testId            string         // stable across runs (test_case_key)
  displayName       string
  suite             string
  framework         enum            // playwright-bdd | jest | junit | trx
  bddFeature?       string          // playwright-bdd only
  bddStep?          string          // from test.step granularity in trace
  status            enum            // passed | failed | flaky | skipped
  durationMs        number
  failureMessage    string
  stackTrace        Frame[]
  attachments       Attachment[]    // screenshot | trace | log refs
  retries           number
  sourceRefs        SourceRef[]
  historicalFlakeRate? number
}
```

## Parser contract
```
IArtifactParser {
  CanParse(artifact) -> bool
  Parse(artifact) -> Failure[]      // emits the Failure Model, nothing format-specific leaks out
}
```
Adding a framework = adding an `IArtifactParser`. No core changes. MVP parsers: JUnitXml, Trx, PlaywrightBdd, Jest, Logs.

## Two clustering signatures (locked)
- `cause_signature = hash(error_type + normalized_message + top 3–5 project-owned stack frames)`
  - **test-agnostic**; used for **within-run** clustering (one cause → many tests, diagnose once).
  - Normalization (before hashing): strip digit runs, UUIDs/GUIDs, hex addresses, timestamps, ports, temp/absolute paths, dynamic IDs in selectors/quoted values (`#user-4821`→`#user-N`); collapse whitespace; **do not lowercase**. Stack = project frames only, line numbers dropped, file+method kept.
- `failure_signature = hash(test_case_key + cause_signature + context_hash + prompt_version + model)`
  - narrow; used for **cross-run** cache (reuse verdict only for same test/cause/code/prompt/model).
- Fan out **category + shared reasoning only**, never the fix verbatim; eject members whose test file/Gherkin step differs materially. Track cluster purity. `--no-cluster` override always available.

## AI abstraction (no vendor SDK outside `Ai/Providers/`)
```
IAiProvider          // one vendor: Send(AiRequest) -> AiResponse (+ normalized usage)
IAiProviderRouter    // pick provider+model per task/policy; fallback on outage
IAiPromptRunner      // THE choke point: render versioned prompt, call router,
                     //   enforce JSON schema, run validators, retry-once, emit usage
IAiUsageTracker      // 1 row/request: provider, model, in/out tokens, cost, latency,
                     //   prompt_version, feature, projectId, runId
IAiModelPolicyService// (task, config, risk) -> model tier; enforce cost caps
```
Model policy tiers: classification→cheap/fast; complex diagnosis (escalation)→stronger; code suggestions→stronger (only when enabled); privacy/local→later.
Every feature calls `IAiPromptRunner` — never a provider directly.

## Root-cause categories (closed enum)
`selector_issue | race_condition | timeout | test_data_cleanup | environment | api_backend_failure | auth_session | assertion_issue | network_issue | product_bug | bad_test_design | unknown`

## Test recommendations (closed enum)
`keep_bdd | to_jest | to_integration | duplicate | low_roi | high_flake_cost | missing_lower_coverage | risky_keep`

## Confidence & publishing
- Confidence = number + band (low | medium | high), driven by evidence count, validated file refs, heuristic/AI agreement, historical signal.
- `confidence.prPublishThreshold` default `high`. PR comment = medium/high only. Build summary + dashboard = everything incl. low-confidence "needs review".

## Code suggestion contract (gated, off by default, review-only)
Output per suggestion: `filePath, reason, beforeAfter, diff, riskLevel, confidence, relatedEvidence, verificationCommand`.
Hard rules: patch must apply cleanly against the **exact retrieved file content**; refuse high-risk/security/migration/weak-evidence/uncontextualized; never auto-apply.

## Config
Canonical example: `spectrace.config.example.yml`. Schema-validated; CLI fails fast on invalid config.

## Persistence
EF Core with **PostgreSQL** (single provider — no SQL Server portability). Use EF Core normally; Postgres-specific features are fine. Cross-run cache lives in the DB, not process memory.

## CLI boundary
The CLI is native .NET and calls `SpecTrace.Core` in-process — there is no cross-process protocol. The only "contract" is the **report shape** the CLI writes to stdout / a file: the JSON report schema (run summary + per-failure diagnosis + evidence). Keep that schema stable; the dashboard upload and CI publishing both consume it.
