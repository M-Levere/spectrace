# SpecTrace

AI-assisted test-intelligence for engineering teams. Ingests CI test artifacts (playwright-bdd, Jest, JUnit XML, .NET TRX), diagnoses failed/flaky tests with evidence-backed root causes, and recommends test-suite improvements (incl. BDD→Jest). Optional, review-only code suggestions. Provider-agnostic AI. Runs CLI-only, self-hosted, or in-pipeline.

> **Status: Phase 1 complete.** Demo app + fixture bundles done. Parser (Phase 2) is next.

---

## Codebase map

```
spectrace/
│
├── src/
│   └── SpecTrace.Core/          # The analysis brain — parsers, heuristics, AI, reporting
│                                # Everything important lives here. Referenced by all apps.
│
├── apps/
│   ├── cli/                     # Native .NET console app — the primary user-facing entry point
│   │                            # Calls SpecTrace.Core directly (no subprocess/spawn)
│   ├── api/                     # ASP.NET Core API — upload artifacts, serve dashboard data
│   ├── worker/                  # Background worker — async diagnosis jobs
│   └── dashboard/               # Next.js frontend — run overview, diagnosis detail, patch panel
│
├── tests/
│   ├── SpecTrace.Core.Tests/
│   ├── SpecTrace.Cli.Tests/
│   └── SpecTrace.Api.Tests/
│
├── demo/                        # Sample test projects used to generate fixture bundles
│   ├── playwright-bdd/          # Gherkin .feature files + TypeScript step defs
│   ├── jest/                    # Jest test files covering the same scenarios
│   └── dotnet/                  # xUnit tests — run as-is with `dotnet test`
│
├── docs/
│   ├── PLAN.md                  # Full technical plan — architecture, AI strategy, schema, phases
│   └── examples/                # Pre-generated fixture bundles (committed, parser tests run against these)
│       ├── playwright-bdd/      # passing / selector-failure / timeout / assertion / flaky
│       ├── jest/                # passing / failing-assertion / failing-timeout / flaky
│       ├── trx/                 # passing / failing-assertion / failing-timeout / flaky
│       └── junit/               # passing / failing-assertion / failing-timeout / flaky
│
├── scripts/
│   ├── generate-fixtures.ps1    # Regenerates all docs/examples/ bundles from scratch
│   └── verify-fixtures.ps1      # Smoke-checks that all expected fixture files exist (exit 0/1)
│
├── infra/                       # Docker Compose, DB migrations, deployment config
├── config/                      # App configuration files
│
├── CLAUDE.md                    # Operating brief + locked decisions for Claude Code
├── CONTRACTS.md                 # Stable shapes: Failure Model, AI interfaces, enums
├── TASKS.md                     # Phase-by-phase work order with acceptance criteria
└── spectrace.config.example.yml # Canonical config reference
```

---

## Key documents

| File | Purpose |
|---|---|
| `docs/PLAN.md` | Full architecture, AI strategy, DB schema, all 12 phases. **Start here.** |
| `TASKS.md` | Work order — what's done, what's next, acceptance criteria per phase |
| `CONTRACTS.md` | Locked interfaces and data shapes. Treat as immutable unless explicitly changed |
| `CLAUDE.md` | Rules for working in this repo with Claude Code |

---

## Where to look for what

**"Where does the actual analysis logic go?"** → `src/SpecTrace.Core/`

**"Where is the CLI?"** → `apps/cli/` — it calls `SpecTrace.Core` directly in-process

**"Where are the test input files the parsers run against?"** → `docs/examples/`

**"How do I regenerate the fixture files?"** → `pwsh scripts/generate-fixtures.ps1`

**"Where are the demo test projects?"** → `demo/` — source for the fixtures; the .NET one runs standalone with `dotnet test`

**"Where's the web UI?"** → `apps/dashboard/` (Next.js, pnpm)

---

## Working on this with Claude Code

1. Read `CLAUDE.md`, then `docs/PLAN.md`, then `TASKS.md`.
2. Work one phase at a time, in order. Don't start a phase until the prior phase's acceptance passes.
3. Tests ship with each phase — AI tests use the mock provider (no live model calls in CI).
