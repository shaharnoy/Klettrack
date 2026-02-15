# Supabase Sync Scale Validation

## Goal
Exercise push batching, pull pagination, and delete tombstones under higher mutation volume for v2 entities.

## Script
- `scripts/supabase_sync_scale_validation.mjs`

## Required env vars
- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_TEST_EMAIL`
- `SUPABASE_TEST_PASSWORD`
- Optional: `SUPABASE_SCALE_UPSERT_COUNT` (default 120)

## Command
```bash
node scripts/supabase_sync_scale_validation.mjs
```

## Pass conditions
- All upsert batches acknowledged with no failures/conflicts.
- Pulled upsert docs match inserted IDs for `session_items`, `timer_laps`, and `climb_entries`.
- Delete tombstones appear for all inserted IDs across those entities.
- Pagination path exercised (`pageCount > 1`).
