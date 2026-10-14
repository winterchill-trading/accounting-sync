open! Core
open Accounting_sync
open Helpers

let%expect_test "a month of activity, one entry per transaction and currency" =
  let export = Export.run ~mapping:full_mapping october in
  List.iter export.entries ~f:print_entry;
  print_s [%sexp (export.netted_out : Entry_key.t list)];
  [%expect {|
    deposit-1:EUR  2026-10-01  EUR  "SEPA in 77"
      Dr     1000        500.00  bank:central
      Cr     2000        500.00  customer:1  [Cost centre=retail]
    deposit-2:EUR  2026-10-02  EUR  "deposit"
      Dr     1000       1200.00  bank:central
      Cr     2000       1200.00  customer:2  [Cost centre=business]
    fee-1:EUR  2026-10-03  EUR  "monthly fee"
      Dr     2000          2.50  customer:1  [Cost centre=retail]
      Cr     4000          2.50  income:fees
    fx-9:sell:EUR  2026-10-05  EUR  "FX 9"
      Dr     2000        100.00  customer:2  [Cost centre=business]
      Cr     1100         99.50  fx:settlement
      Cr     4000          0.50  income:fees
    fx-9:sell:GBP  2026-10-05  GBP  "FX 9"
      Dr     1100         85.00  fx:settlement
      Cr     2000         85.00  customer:2  [Cost centre=business]
    settle-1:EUR  2026-10-08  EUR  "CARD_AUTH"
      Dr     2000         20.00  customer:1  [Cost centre=retail]
      Cr     2100         20.00  clearing:cards
    scheme-1:EUR  2026-10-09  EUR  "transfer"
      Dr     2100         20.00  clearing:cards
      Cr     1000         20.00  bank:central
    (auth-1:EUR)
    |}]
;;

let%expect_test "an unmapped account blocks its transactions and is reported" =
  let export = Export.run ~mapping october in
  print_s [%sexp (export.blocked : Export.Blocked.t list)];
  print_s [%sexp (Export.unmapped export : Export.Unmapped.t list)];
  print_s [%sexp (List.length export.entries : int)];
  [%expect {|
    (((key settle-1:EUR) (date 2026-10-08)
      (unmapped ((clearing:cards "20.00 EUR"))))
     ((key scheme-1:EUR) (date 2026-10-09)
      (unmapped ((clearing:cards "20.00 EUR")))))
    (((account clearing:cards) (entries 2) (amounts ("40.00 EUR"))))
    5
    |}]
;;

let%expect_test "period, selection and exchange rates" =
  let fx currency date =
    if Money.Currency.equal currency gbp
    then
      Some
        (Money.Rate.create
           ~base:gbp
           ~quote:eur
           ~price:(Q.of_string "1.17")
           ~at:(Time_ns.of_date_ofday ~zone:Time_float.Zone.utc date Time_ns.Ofday.start_of_day)
           ~source:"test"
         |> Or_error.ok_exn)
    else None
  in
  let export =
    Export.run
      ~mapping:full_mapping
      ~from:(oct 3)
      ~to_:(oct 5)
      ~touching:(Ledger.Account_id.equal (id "customer:2"))
      ~fx
      october
  in
  List.iter export.entries ~f:print_entry;
  [%expect {|
    fx-9:sell:EUR  2026-10-05  EUR  "FX 9"
      Dr     2000        100.00  customer:2  [Cost centre=business]
      Cr     1100         99.50  fx:settlement
      Cr     4000          0.50  income:fees
    fx-9:sell:GBP  2026-10-05  GBP @ 1.17  "FX 9"
      Dr     1100         85.00  fx:settlement
      Cr     2000         85.00  customer:2  [Cost centre=business]
    |}]
;;
