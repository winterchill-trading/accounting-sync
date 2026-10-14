open! Core
open Accounting_sync
open Helpers

(* A changed digest means old bytes no longer decode: add a Stable.V2 instead of editing
   V1, and keep V1 readable. *)
let%expect_test "stable bin_prot digests" =
  List.iter
    [ "Account_code", [%bin_digest: Account_code.Stable.V1.t]
    ; "Entry_key", [%bin_digest: Entry_key.Stable.V1.t]
    ; "Chart.Account_type", [%bin_digest: Chart.Account_type.Stable.V1.t]
    ; "Chart.Account", [%bin_digest: Chart.Account.Stable.V1.t]
    ; "Chart", [%bin_digest: Chart.Stable.V1.t]
    ; "Tracking.Category", [%bin_digest: Tracking.Category.Stable.V1.t]
    ; "Tracking.Assignment", [%bin_digest: Tracking.Assignment.Stable.V1.t]
    ; "Journal_entry.Line", [%bin_digest: Journal_entry.Line.Stable.V1.t]
    ; "Journal_entry", [%bin_digest: Journal_entry.Stable.V1.t]
    ; "Mapping.Rule", [%bin_digest: Mapping.Rule.Stable.V1.t]
    ; "Mapping", [%bin_digest: Mapping.Stable.V1.t]
    ; "Reason", [%bin_digest: Reason.Stable.V1.t]
    ; "Status", [%bin_digest: Status.Stable.V1.t]
    ; "Period", [%bin_digest: Period.Stable.V1.t]
    ; "Period_lock", [%bin_digest: Period_lock.Stable.V1.t]
    ; "Organisation", [%bin_digest: Organisation.Stable.V1.t]
    ; "Connection", [%bin_digest: Connection.Stable.V1.t]
    ; "Tracker.Item", [%bin_digest: Tracker.Item.Stable.V1.t]
    ; "Tracker", [%bin_digest: Tracker.Stable.V1.t]
    ]
    ~f:(fun (name, digest) -> printf "%-20s %s\n" name digest);
  [%expect {|
    Account_code         d9a8da25d5656b016fb4dbdc2e4197fb
    Entry_key            d9a8da25d5656b016fb4dbdc2e4197fb
    Chart.Account_type   65757fe816f9c61e73473030788a7966
    Chart.Account        1c503dfdbce092a3cb71a9669d9b4632
    Chart                3a4e8d2e453c17c53b9c7ec646c66efc
    Tracking.Category    150e9671c249cc611fb3964f25be63bd
    Tracking.Assignment  3fd95083d8d3721b84030f270a0d81a0
    Journal_entry.Line   4694b762b3a3b72eddf33033b4a94e66
    Journal_entry        50069127839cd60b71c9d5a3d8034170
    Mapping.Rule         7d65b227629c5da84cc03efc071b911d
    Mapping              1fc2904a626ea2b39fe7358491e48c40
    Reason               2b9ccfa0d587f374cf4b8f304a262e71
    Status               349426094347f0703efe7b7cd6824f79
    Period               82e84542c03e3ad3adbe4012899b29fb
    Period_lock          1bd28bfbe22df948eec3733337119854
    Organisation         627f4ecae421545a9cfe9d7a6b4b70e1
    Connection           8778235a0be92c5eac4977a3140b900e
    Tracker.Item         23ddc17a23d60728eaf490bff3c74b36
    Tracker              202b6ceb72b9087ba72c438d8fe33bff
    |}]
;;

let round_trip (type a) (module M : Binable.S with type t = a) (x : a) =
  Bin_prot.Reader.of_string M.bin_reader_t (Bin_prot.Writer.to_string M.bin_writer_t x)
;;

let%expect_test "values round trip through bin_prot and sexp; reading validates" =
  [%test_result: Chart.t] (round_trip (module Chart.Stable.V1) chart) ~expect:chart;
  [%test_result: Chart.t] (Chart.Stable.V1.t_of_sexp (Chart.Stable.V1.sexp_of_t chart)) ~expect:chart;
  [%test_result: Mapping.t] (round_trip (module Mapping.Stable.V1) full_mapping) ~expect:full_mapping;
  let tracker, _ =
    Tracker.stage Tracker.empty (Export.run ~mapping:full_mapping october).entries
  in
  [%test_result: Tracker.t] (round_trip (module Tracker.Stable.V1) tracker) ~expect:tracker;
  [%test_result: Tracker.t]
    (Tracker.Stable.V1.t_of_sexp (Tracker.Stable.V1.sexp_of_t tracker))
    ~expect:tracker;
  let lock =
    Period_lock.lock_period
      (Period_lock.lock_through Period_lock.none (oct 3))
      (Period.of_date (oct 9))
  in
  [%test_result: Period_lock.t] (round_trip (module Period_lock.Stable.V1) lock) ~expect:lock;
  print_s [%sexp (Period_lock.Stable.V1.sexp_of_t lock : Sexp.t)];
  let unbalanced =
    Sexp.of_string
      "((key k:EUR) (transaction k) (date 2026-10-01) (currency EUR) (fx ()) (narration \
       \"\") (reference \"\") (lines (((account 1000) (side Debit) (amount \"1.00 EUR\") \
       (description \"\") (tracking ()) (sources ())) ((account 4000) (side Credit) \
       (amount \"2.00 EUR\") (description \"\") (tracking ()) (sources ())))))"
  in
  print_s
    [%sexp
      (Or_error.try_with (fun () -> Journal_entry.Stable.V1.t_of_sexp unbalanced)
       : Journal_entry.t Or_error.t)];
  [%expect {|
    ((through (2026-10-03)) (periods (2026-10)))
    (Error ("unbalanced entry" (key k:EUR) (debits_minus_credits "-1.00 EUR")))
    |}]
;;
