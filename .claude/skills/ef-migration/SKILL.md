---
name: ef-migration
description: Make EF Core schema or migration changes in SpecTrace.Core/Persistence. Use when adding or altering entities, DbContext config, indexes, or migrations. Keeps the data layer portable between PostgreSQL (dev/test) and SQL Server / Azure SQL (company deploy).
---

# EF Core schema & migrations

SpecTrace develops on PostgreSQL but must run on a company's SQL Server / Azure SQL. The data layer stays provider-agnostic so that's a config swap, not a rewrite.

## Rules
- Keep `DbContext` provider-agnostic. **Avoid provider-specific features**: Postgres `jsonb` operators, array columns, `ON CONFLICT`/upsert, `gen_random_uuid()`, full-text search. If you need JSON, store it as a string/`text` column and (de)serialize in code so both providers behave the same.
- Use portable types: GUID keys (`uuid` / `uniqueidentifier`), UTC timestamps (`timestamptz` / `datetimeoffset`), `string` for long text. Let the provider map them; don't hardcode column types.
- The cross-run cache (`failure_signature`) and within-run clustering (`cause_signature`) live in the DB, not process memory — index them.
- Follow the schema in `docs/PLAN.md §4.J` and the signature definitions in `CONTRACTS.md`.

## Workflow
1. Change entities + `DbContext` configuration (provider-agnostic).
2. Generate migrations for **both** providers (they emit different SQL):
   - Postgres: the default dev provider.
   - SQL Server: the company provider.
   Keep them in per-provider migration folders.
3. Apply against a local Postgres (Docker) and verify.
4. If you used anything that doesn't translate, refactor until it does — don't special-case one provider.

## Testing
- Run repository/integration tests against Postgres in CI.
- Add a smoke check that the SQL Server migration generates without provider-specific errors.

## Done when
- Both provider migrations generate and apply; no Postgres-only feature in the model.
- Commit: `feat(db): <change>` (+ `chore(db): migrations <change>`).
