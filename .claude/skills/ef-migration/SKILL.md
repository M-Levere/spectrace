---
name: ef-migration
description: Make EF Core schema or migration changes in SpecTrace.Core/Persistence. Use when adding or altering entities, DbContext config, indexes, or migrations. Single provider — PostgreSQL.
---

# EF Core schema & migrations

SpecTrace uses **PostgreSQL** via EF Core, single provider. (The old SQL Server portability requirement was company-specific and has been dropped for the portfolio.) Use EF Core normally.

## Rules
- Postgres-specific features are fine (jsonb, arrays, etc.) — use them where they help.
- Use sensible types: GUID keys, UTC timestamps (`timestamptz`), `text` for long strings.
- The cross-run cache (`failure_signature`) and within-run clustering (`cause_signature`) live in the DB, not process memory — index them.
- Follow the schema in `docs/PLAN.md §4.J` and the signature definitions in `CONTRACTS.md`.

## Workflow
1. Change entities + `DbContext` configuration.
2. Add an EF Core migration.
3. Apply against local Postgres (Docker) and verify.

## Testing
- Run repository/integration tests against Postgres in CI (a Postgres service container).

## Done when
- Migration generates and applies against Postgres; schema matches PLAN §4.J.
- Commit: `feat(db): <change>` (+ `chore(db): migration <change>`).
