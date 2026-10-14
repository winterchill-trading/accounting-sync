# lib/

The `accounting-sync` library, wrapped as `Accounting_sync` (`accounting_sync.ml` lists
the modules in groups for odoc). Built and tested from the repository root; see
`../AGENTS.md` for commands.

- Data flow: `Export.run` (ledger records + `Mapping`) -> `Journal_entry.t list` ->
  `Tracker.stage` -> `Sync.push` (`Check`, `Batch`, `Connector.post`) -> `Sync.poll` ->
  `Reconciliation.run`.
- Add a module with its `.mli`, an alias in `accounting_sync.ml`, and, for a persisted
  type, a `Stable.V1` plus a digest line in `../test/test_stable.ml`.
- `Simulated` must keep `Connector.S`'s contract (idempotent `post` per push key, an
  answer per key); `Check` holds the validation order it shares with syncs.
