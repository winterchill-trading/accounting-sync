An example journal and its mapping:

  $ accounting-sync example -journal j.bin
  $ accounting-sync mapping-example > mapping.sexp
  $ cat mapping.sexp
  ((rules
    (((Account bank:central) 1000) ((Prefix fx:) 1100)
     ((Prefix customer:) 2000) ((Account clearing:cards) 2100)
     ((Class Income) 4000)))
   (tracking ((segment "Cost centre"))))

Export the first week; the card clearing rule is removed to show the blocked report:

  $ accounting-sync export -journal j.bin -mapping mapping.sexp -from 2026-10-01 -to 2026-10-07
  deposit-1:EUR  2026-10-01  EUR  SEPA in 77
    Dr 1000         500.00
    Cr 2000         500.00  Cost centre=retail
  deposit-2:EUR  2026-10-02  EUR  deposit
    Dr 1000        1200.00
    Cr 2000        1200.00  Cost centre=business
  fee-1:EUR  2026-10-03  EUR  monthly fee
    Dr 2000           2.50  Cost centre=retail
    Cr 4000           2.50
  fx-9:sell:EUR  2026-10-05  EUR  FX 9
    Dr 2000         100.00  Cost centre=business
    Cr 1100          99.50
    Cr 4000           0.50
  fx-9:sell:GBP  2026-10-05  GBP  FX 9
    Dr 1100          85.00
    Cr 2000          85.00  Cost centre=business
  $ sed 's/ ((Account clearing:cards) 2100)//' mapping.sexp > partial.sexp
  $ accounting-sync export -journal j.bin -mapping partial.sexp -from 2026-10-07 -to 2026-10-31
  unmapped clearing:cards: 2 entries, 40.00 EUR

Sync the month to a simulated system whose books are closed through the 2nd, and which
rejects one entry:

  $ accounting-sync sync -journal j.bin -mapping mapping.sexp -from 2026-10-01 -to 2026-10-31 -locked-through 2026-10-02 -reject-next 1
  JE-0001 fee-1:EUR:1          rejected validation_error
  JE-0002 fx-9:sell:EUR:1      posted
  JE-0003 fx-9:sell:GBP:1      posted
  JE-0004 settle-1:EUR:1       posted
  JE-0005 scheme-1:EUR:1       posted
  refused deposit-1:EUR: period_locked
  refused deposit-2:EUR: period_locked
  entries 7 posted 4 rejected 3 blocked 0 reconciled false
