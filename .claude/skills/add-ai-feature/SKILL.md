---
name: add-ai-feature
description: Add or modify any AI-backed feature in SpecTrace (diagnosis, code suggestions, BDD-to-Jest recommendations, classification). Use whenever code will call an LLM/model provider, build a prompt, parse model output, or touch the AI provider abstraction. Enforces evidence, validation, cost, and provider rules.
---

# Add an AI-backed feature

Every AI call in SpecTrace goes through one path and obeys the same rules. If you're tempted to call a provider directly or skip a validator, stop — that's the failure mode this skill prevents.

## Non-negotiable rules
- **Parse/heuristics first.** Never call a model for something deterministic. Let the heuristic classifier short-circuit obvious cases before any AI.
- **One choke point.** Call `IAiPromptRunner` only — never an `IAiProvider` implementation directly from a feature. The runner renders the versioned prompt, calls the router, enforces JSON schema, retries once on bad JSON, runs validators, and emits usage.
- **No vendor SDK outside `src/SpecTrace.Core/Ai/Providers/`.** The Phase-4 architecture test enforces this; don't defeat it.
- **Structured JSON only.** The prompt must demand strict JSON matching a schema. Parse + validate; never regex model prose.
- **Cite evidence.** Output must reference retrieved artifact/source context. A response with no citation is low-confidence and gets flagged, not shown as fact.
- **Track usage.** Every call records provider, model, in/out tokens, cost, latency, prompt version, and the feature that triggered it via `IAiUsageTracker`.
- **Respect model policy + cost caps.** Get the model tier from `IAiModelPolicyService` (cheap/fast for classification, stronger only on escalation or code suggestions). On cap hit, degrade to heuristic-only and flag it — never fail the build.

## Prompts
- Prompt templates live in `src/SpecTrace.Core/Ai/Prompts/`, **versioned**. Don't edit a shipped version in place — add a new version so quality changes are attributable.

## Anti-hallucination (wire the matching validator in `Ai/Validation/`)
- Drop any cited file path not present in retrieved context.
- Reject generic fixes ("increase timeout") that lack specific evidence.
- UI-category diagnoses require a trace/screenshot citation or get demoted.
- Code patches must apply cleanly against the exact retrieved file content, or they're discarded.

## Testing
- Use the **mock `IAiProvider`** returning canned JSON. **No live model calls in unit/CI tests.**
- Assert: schema validation, retry-once on bad JSON, citation enforcement, usage recorded, cost-cap degradation.

## Done when
- Feature works through `IAiPromptRunner`, is cited, validated, tracked, and tested against the mock.
- Commit: `feat(ai): <feature>` (+ `feat(ai): <feature> validators`).
