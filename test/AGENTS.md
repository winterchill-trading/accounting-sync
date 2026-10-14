# test/

Inline expect tests (`accounting_sync_test` library), Quickcheck properties
(`test_properties.ml`), pinned stable digests (`test_stable.ml`) and the command's cram
test (`cli.t/run.t`). `helpers.ml` builds a month of ledger records without a journal file.

- Run with `@accounting-sync/runtest` (see `../AGENTS.md`); promote with `dune promote
  --root ..` and the same `DUNE_BUILD_DIR`, after reading the diff.
- A changed digest in `test_stable.ml` means old bytes no longer decode: add a `V2`.
- Async tests use `Async.Thread_safe.block_on_async_exn` inside a plain expect test.
