# .github/

`workflows/ci.yml`: infra `ox-setup` with sibling pins, then build, test, the quickstart
example and the shared `obj-magic` workflow.

- Keep the pins in dependency order (`fixed-decimal`, `money`, `ledger`) and in step with
  the `depends` field of `../dune-project`.
- Check CI with one `gh run list --limit 1` and at most one `gh run watch <id> --exit-status`.
