# accounting-sync

Export of double-entry ledger journals to external accounting systems. It takes the
records of a [`ledger`](https://github.com/winterchill-trading/ledger) journal and turns
them into journal entries an accounting package accepts: one entry per transaction and
currency, lines on the package's own account codes with tracking categories, an
idempotent key per entry, a status per entry, batches per accounting period that respect
period locks, and a reconciliation that shows whether the books on both sides agree.

Amounts come from [`money`](https://github.com/winterchill-trading/money): exact integer
minor units, no floats. The library is pure and never persists anything: mappings,
trackers, connections and locks are values with stable binary forms that a service
stores however it likes.

## Why separate

A bank or payment company keeps its own ledger as the system of record, but its finance
team closes the books in an accounting package. The bridge between the two is the same
everywhere and easy to get wrong: which ledger accounts land on which chart codes, what
happens to a customer account nobody mapped yet, how a retry avoids posting a transfer
twice, what to do when a period is already closed, and how to prove at month end that
what the package holds is what the ledger says. None of that depends on a particular
package's API, so it lives here once, with properties tested, and adapters for real
systems only translate requests.

## Quick start

```sh
dune build
dune exec accounting-sync -- example -journal /tmp/october.bin
dune exec accounting-sync -- mapping-example > /tmp/mapping.sexp
dune exec accounting-sync -- export -journal /tmp/october.bin -mapping /tmp/mapping.sexp
dune exec accounting-sync -- sync -journal /tmp/october.bin -mapping /tmp/mapping.sexp \
  -from 2026-10-01 -to 2026-10-31 -locked-through 2026-10-02 -reject-next 1
dune exec ./examples/quickstart.exe
```

```
JE-0001 fee-1:EUR:1          rejected validation_error
JE-0002 fx-9:sell:EUR:1      posted
JE-0003 fx-9:sell:GBP:1      posted
JE-0004 settle-1:EUR:1       posted
JE-0005 scheme-1:EUR:1       posted
refused deposit-1:EUR: period_locked
refused deposit-2:EUR: period_locked
entries 7 posted 4 rejected 3 blocked 0 reconciled false
```

## Usage

```ocaml
open! Core
open Accounting_sync

let code = Account_code.of_string

let chart =
  Chart.create_exn
    [ Chart.Account.create (code "2000") ~name:"Customer deposits" Liability
    ; Chart.Account.create (code "4000") ~name:"Fee income" Revenue
    ]

let mapping =
  Mapping.create_exn [ Prefix "customer:", code "2000"; Class Income, code "4000" ]

(* [records] come from Ledger.Journal.read or a projection of the journal. *)
let sync ~records ~tracker ~now =
  assert (List.is_empty (Mapping.check mapping ~chart ~categories:[]));
  let export = Export.run ~mapping records in
  (* [Export.unmapped export] lists ledger accounts that still need a rule. *)
  let sim = Simulated.create ~chart ~categories:[] () in
  let org = { Organisation.id = "org-1"; name = "Example Ltd" } in
  Sync.push (Simulated.connector sim) org tracker ~entries:export.entries ~now
```

`examples/quickstart.ml` is the complete program, built and run in CI.

## Model

| Module | What it is |
|---|---|
| `Account_code`, `Entry_key`, `Push_key`, `Remote_id` | Validated text ids, distinct types |
| `Chart` | The external chart: code, name, type (asset, bank, liability, equity, revenue, expense), archived flag |
| `Tracking` | Tracking categories with options; at most one option per category on a line |
| `Journal_entry` | Key, ledger transaction, date, currency, optional rate to the reporting currency, narration, reference, balanced lines with sources |
| `Mapping` | Rules from ledger accounts to codes: exact account, longest prefix, tag, account class; tracking from account tags; `check` against a chart |
| `Export` | Ledger records to entries: one per transaction and currency, netted per code and tracking; blocked transactions and the unmapped-account report |
| `Period`, `Period_lock`, `Batch` | Monthly periods, a lock date plus closed months, batches of bounded size that never mix periods |
| `Reason`, `Status`, `Tracker` | Rejection reasons, the entry state machine, the status book with attempts and replacements |
| `Connection` | Consent and organisation selection: pending, connected, disconnected, cancelled |
| `Connector` | The module type an adapter implements, and an existential wrapper |
| `Simulated` | An in-memory system: consent, organisations, chart, lock date, idempotent posts, entry numbers, polls, voids, test hooks |
| `Check`, `Sync`, `Reconciliation` | Local checks, push/poll/void over a connector, and the three-way period reconciliation |

### Rules

- One ledger transaction (a booked record: an entry, an approved adjustment, or a group
  of linked entries) becomes one entry per currency it moves, keyed
  `<transaction key>:<currency>`. Exporting the same journal again gives the same keys
  and digests.
- Postings that map to the same code and tracking options are netted into one line. A
  hold's pending sub-account maps like its parent, so a hold placed and released inside
  one transaction leaves nothing; a transaction that nets to zero produces no entry.
- A transaction with a posting the mapping cannot place is not exported in part: it is
  blocked, and `Export.unmapped` reports the accounts to map, with entry counts and
  amounts.
- Every attempt to post an entry carries the push key `<entry key>:<attempt>`. A request
  that fails is resent under the same key; a retry after a rejection or a void moves to
  the next attempt.
- Entries dated in a locked period (the system's lock date, a local lock date, or a
  closed month) are refused locally with `period_locked` and never sent.
- An entry whose ledger content changes after it was submitted or posted is not
  re-sent: the new content waits as a replacement until the remote entry is voided.

```
Pending --accepted--> Submitted --posted--> Posted --voided--> Voided
   |                     |                                       |
   +------posted---------|-------------------> Posted            |
   +------rejected-------+---rejected--> Rejected --retry--> Pending
   +------voided-----------------------> Voided   --retry--> Pending
```

Rejection reasons: `unmapped_account`, `unbalanced`, `unknown_tracking`,
`period_locked`, `validation_error`. The last two are retryable as they are; the others
need a mapping, chart or content change first.

### Writing a connector

Implement `Connector.S` for the system: consent URL, completing a grant into the list of
organisations it covers, disconnect, chart, tracking categories, the system's own lock
date, `post`, `poll`, `void` and a view URL. `post` must be idempotent per push key and
answer every key; `poll` answers only ids it knows. A refusal is an `Answer.Rejected`,
not an error; errors are for transport failures, after which the entries stay pending
under the same push keys.

### Reconciliation

`Reconciliation.run` compares, per currency and chart code, the net movement of the
ledger's postings in the period, of the entries an export builds now, and of the entries
the tracker says are posted, and counts entries matched, not pushed, pending, rejected,
changed after posting, extra (posted but no longer exported) and blocked. A period
reconciles when every count but `matched` is zero and the three views agree.

## Tests

Expect tests cover the export of a month of activity (deposits, a fee, an exchange as
linked legs, a card hold and capture, a scheme settlement), mapping precedence, periods,
locks and batching, the status transition table, end-to-end syncs against the simulated
system (consent, repeats, rejections and retries, changes and voids, a remote lock,
decisions on poll), reconciliation, and the command (`test/cli.t`). Quickcheck checks
that exported net movement per code equals the ledger's under a complete mapping, that
entries balance and keys are unique and deterministic, that batches partition their
input, and that staging is idempotent and push keys never repeat across retries. Stable
digests are pinned in `test/test_stable.ml`.

## Known gaps

- No adapter for a real accounting package yet; each belongs in its own package next to
  its HTTP client.
- Entries are dated by day in UTC; a ledger whose business day is in another zone should
  export by `Business_date`.
- A system that caps the number of tracking categories per line (two is common) is not
  checked locally; the system rejects such entries with `unknown_tracking` or
  `validation_error`.

## Docs

- `AGENTS.md`: guide for AI coding agents working in this repository (one per
  directory).
- `CHANGES.md`.
- odoc: `dune build @doc`.
