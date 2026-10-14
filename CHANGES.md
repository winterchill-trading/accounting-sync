# Changes

All notable changes to this library. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow semantic
versioning once released.

## Unreleased

### Added

- `Journal_entry`: a system-neutral journal entry (date, currency, optional exchange
  rate, narration, reference, lines on external account codes with tracking options),
  validated on creation and on decoding, with a content digest.
- `Chart` and `Tracking`: an external chart of accounts with account types and archived
  accounts; tracking categories and per-line assignments.
- `Mapping`: rules from ledger accounts to chart codes (exact account, longest prefix,
  tag, account class), pending sub-accounts mapped through their parent, tracking from
  account tags, and `check` against a chart.
- `Export`: one entry per ledger transaction and currency under an idempotent
  `Entry_key`, netting per code and tracking, blocked transactions and an unmapped
  account report, period and account selection, exchange rates per currency and day.
- `Status`, `Reason` and `Tracker`: the entry state machine (pending, submitted, posted,
  rejected with a reason, voided), push keys per attempt, and replacements for entries
  that changed after they were sent.
- `Period`, `Period_lock` and `Batch`: monthly periods, lock dates and closed months,
  batches that never mix periods.
- `Connection`, `Connector.S` and `Simulated`: the consent and organisation selection
  flow, the module type an accounting system adapter implements, and a deterministic
  in-memory system with test hooks.
- `Check`, `Sync` and `Reconciliation`: local checks before sending, push/poll/void
  syncs, and a three-way reconciliation (ledger, exported, posted) per account and
  currency.
- `accounting-sync` command (`example`, `mapping-example`, `export`, `sync`) and a
  quickstart example run in CI.
