(lang dune 3.17)

(name accounting-sync)

(generate_opam_files true)

(license MIT)

(authors "WinterChill AI")

(maintainers "hello@winterchill.xyz")

(source
 (github winterchill-trading/accounting-sync))

(homepage "https://github.com/winterchill-trading/accounting-sync")

(bug_reports "https://github.com/winterchill-trading/accounting-sync/issues")

(documentation "https://github.com/winterchill-trading/accounting-sync#readme")

(package
 (name accounting-sync)
 (synopsis
  "Export of double-entry ledger journals to external accounting systems")
 (description
  "accounting-sync turns the transactions of a double-entry ledger into journal entries for an external accounting system: a system-neutral entry model (date, lines with external account codes, tracking categories, currency and exchange rate, narration), a mapping from ledger accounts to the system's chart of accounts with validation and unmapped-account reports, one entry per transaction and currency with idempotent entry keys, an entry status state machine (pending, submitted, posted, rejected with a reason, voided), batching by accounting period with period locks, a connector module type (consent and organisation selection, chart retrieval, posting, status polling) with a deterministic simulated connector, and a reconciliation of exported totals against the ledger. Pure and exact; the library never persists anything. Requires the OxCaml compiler (through its money dependency).")
 (tags
  (accounting bookkeeping journal ledger export banking oxcaml))
 (depends
  oxcaml
  (ocaml
   (and
    (>= 5.2.0)
    (< 5.3~)))
  dune
  (core (and (>= v0.18~preview.130.106+341) (< v0.19~)))
  (core_unix (and (>= v0.18~preview.130.106+341) (< v0.19~)))
  (async_kernel (and (>= v0.18~preview.130.106+341) (< v0.19~)))
  (async (and (>= v0.18~preview.130.106+341) (< v0.19~)))
  (ppx_jane (and (>= v0.18~preview.130.106+341) (< v0.19~)))
  zarith
  money
  ledger
  (expect_test_helpers_core
   (and
    :with-test
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (odoc :with-doc)))
