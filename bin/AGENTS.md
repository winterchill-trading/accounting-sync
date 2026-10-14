# bin/

The `accounting-sync` command: `example` writes a ledger journal file, `mapping-example`
prints a mapping for it, `export` prints entries and the unmapped-account report, `sync`
pushes to a fresh simulated system and prints the reconciliation verdict.

- Output is pinned by `../test/cli.t/run.t`; change both together.
- Print with Core (`printf`, `print_s`); Async's writer is not flushed by basic commands.
