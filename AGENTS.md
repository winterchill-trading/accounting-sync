# AGENTS.md

Guide for AI coding agents working in this repository. Read this first; the subdirectory
`AGENTS.md` files add detail for `lib/`, `bin/`, `test/`, `examples/` and `.github/`. The
workspace-wide guide is `../oxcaml-claude-skills/AGENTS.md`.

## Purpose

`accounting-sync` exports the transactions of a `ledger` journal to external accounting
systems: one balanced entry per transaction and currency on the system's chart codes, with
idempotent keys, per-entry statuses, period batches and locks, and a reconciliation of what
was posted against the ledger. It is pure: every piece of state is a value; nothing persists.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | The `accounting-sync` library (`Accounting_sync`): ids, `Chart`, `Tracking`, `Journal_entry`, `Mapping`, `Export`, `Period`, `Period_lock`, `Batch`, `Reason`, `Status`, `Tracker`, `Connection`, `Connector`, `Simulated`, `Check`, `Sync`, `Reconciliation` |
| `bin/` | The `accounting-sync` command: `example`, `mapping-example`, `export`, `sync` |
| `test/` | Expect tests, Quickcheck properties, pinned digests, the `cli.t` cram test |
| `examples/` | `quickstart.ml`, the README walk-through, run in CI |
| `.github/` | CI workflow |
| `dune-project` | Package metadata; `dune build` regenerates `accounting-sync.opam` |

## Build, test, docs

Inside the workspace (sibling checkouts and the shared `5.2.0+ox` switch are required), from
this directory:

```sh
DUNE_BUILD_DIR=_build-accounting-sync opam exec --switch 5.2.0+ox -- dune build --root .. @accounting-sync/all
DUNE_BUILD_DIR=_build-accounting-sync opam exec --switch 5.2.0+ox -- dune build --root .. @accounting-sync/runtest
DUNE_BUILD_DIR=_build-accounting-sync opam exec --switch 5.2.0+ox -- dune build --root .. @accounting-sync/doc
```

`DUNE_BUILD_DIR` resolves from the workspace root because of `--root ..`. Promote expect
output with `DUNE_BUILD_DIR=_build-accounting-sync opam exec --switch 5.2.0+ox -- dune promote --root ..`
after reading the diff; only this build directory's corrections are promoted.

Standalone: `opam repo add winterchill https://github.com/winterchill-trading/opam-repository.git`,
then `opam install --deps-only --with-test .` and `dune build && dune test`.

## Conventions

- Every module has an `.mli` with odoc on each public value. `open! Core`, labelled arguments.
- Amounts are `money` minor units; no floats. Exchange rates are `Money.Rate.t` (exact).
- Pure library: trackers, mappings, connections and locks are values; the only effects are
  behind `Connector.S` (Async). Services persist through their own store.
- State machines (`Status`, `Connection`) refuse transitions they do not list; keep the
  transition table test in `test/test_status.ml` in step with any change.
- `Stable` types have pinned digests in `test/test_stable.ml`; add a `V2`, never edit `V1`.
  Validated types (`Journal_entry`, `Chart`, `Mapping`) validate again on decoding.
- `Journal_entry.digest` hashes the stable sexp: any field change alters every digest, which
  makes trackers see every posted entry as changed. Treat it like a stable format.
- Expect tests plus Quickcheck for invariants; comments for humans at non-obvious choices.
- Formatting: `DUNE_BUILD_DIR=_build-accounting-sync opam exec --switch 5.2.0+ox -- dune build --root .. @accounting-sync/fmt --auto-promote`.
  Never run `dune fmt` at the workspace root.
- User-visible changes get a line under "Unreleased" in `CHANGES.md`.

## Dependencies and dependents

- Depends on `money` and `ledger` (plus `fixed-decimal` transitively), core, async_kernel, zarith.
- CI pin order: `fixed-decimal`, `money`, `ledger`.
- No org repository depends on it yet.

## CI

`ci.yml` runs the infra `ox-setup` action with the pins above, then `dune build`, `dune test`,
the quickstart example, and the shared `obj-magic` workflow. Check a run with
`gh run list --limit 1`, then at most one `gh run watch <id> --exit-status`.

## Pitfalls

- `Time_ns.t` sexps print in the machine's zone; types use `Time_ns.Alternate_sexp.t` and
  `Time_ns.Stable.Alternate_sexp.V1.t` so expect output is the same on a Mac and in CI.
- With `open! Async`, `printf`/`print_s` go through an Async writer that a `Command.basic`
  never flushes; `bin/main.ml` uses Core's printing and qualifies Async.
- Record fields shared by several types (`status`, `active`, `remote`) resolve to the last
  type defined; annotate the pattern (`Some (item : Item.t)`).
- Async in one inline test: `Async.Thread_safe.block_on_async_exn` in a plain expect test.
- `Map.of_alist_multi` keeps input order, which `Batch.plan` relies on for stable batch ids.
- A half-written sibling repo can make the workspace build fail; filter output for
  `accounting-sync/`.

## Where to read more

- `README.md`: rules, the status diagram, writing a connector, reconciliation, known gaps.
- `CHANGES.md`, and `../specs/repos/accounting-sync.md` when present.
- `../oxcaml-claude-skills/skills/banking-standards/` and `../oxcaml-claude-skills/GOTCHAS.md`
  ("Product libraries").
- `../oxcaml-claude-skills/AGENTS.md`, the workspace-wide guide.

## Never do

- Install or upgrade opam packages that change the compiler, `core`, `base`, `async` or
  `ppx_jane` on the shared switch; dry-run first.
- Publish, tag or release. Commit credentials or print secrets. Poll CI in a loop.
