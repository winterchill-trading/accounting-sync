open! Core
open Accounting_sync
open Helpers

let%expect_test "periods" =
  let p = Period.of_date (Date.of_string "2024-02-10") in
  printf
    "%s %s..%s next %s prev %s\n"
    (Period.to_string p)
    (Date.to_string (Period.first_day p))
    (Date.to_string (Period.last_day p))
    (Period.to_string (Period.next p))
    (Period.to_string (Period.prev (Period.of_date (Date.of_string "2026-01-05"))));
  print_s [%sexp (Period.of_string_or_error "2026-13" : Period.t Or_error.t)];
  print_s [%sexp (Period.of_string_or_error "2026-10" : Period.t Or_error.t)];
  [%expect {|
    2024-02 2024-02-01..2024-02-29 next 2024-03 prev 2025-12
    (Error (("invalid period" 2026-13) (Failure "Month.of_int_exn 13")))
    (Ok 2026-10)
    |}]
;;

let%expect_test "locks: a lock date never moves back by itself; months lock on their own" =
  let lock = Period_lock.lock_through Period_lock.none (oct 31) in
  let lock = Period_lock.lock_through lock (oct 15) in
  print_s [%sexp (lock.through : Date.t option)];
  let lock =
    Period_lock.lock_period
      (Period_lock.reopen_through lock (Some (oct 15)))
      (Period.of_date (Date.of_string "2026-12-01"))
  in
  List.iter [ oct 15; oct 16; Date.of_string "2026-12-24"; Date.of_string "2026-11-30" ]
    ~f:(fun d -> printf "%s %b\n" (Date.to_string d) (Period_lock.is_locked lock d));
  [%expect {|
    (2026-10-31)
    2026-10-15 true
    2026-10-16 false
    2026-12-24 true
    2026-11-30 false
    |}]
;;

let%expect_test "batches never mix periods and skip locked ones" =
  let export = Export.run ~mapping:full_mapping october in
  let sept =
    Journal_entry.create
      ~key:(Entry_key.of_string "late:EUR")
      ~transaction:(key "late")
      ~date:(Date.of_string "2026-09-30")
      ~currency:eur
      [ { account = code "1000"; side = Debit; amount = amount "1.00 EUR"; description = ""; tracking = []; sources = [] }
      ; { account = code "4000"; side = Credit; amount = amount "1.00 EUR"; description = ""; tracking = []; sources = [] }
      ]
    |> Or_error.ok_exn
  in
  let nov =
    Journal_entry.create
      ~key:(Entry_key.of_string "early:EUR")
      ~transaction:(key "early")
      ~date:(Date.of_string "2026-11-01")
      ~currency:eur
      sept.lines
    |> Or_error.ok_exn
  in
  let lock = Period_lock.lock_through Period_lock.none (Date.of_string "2026-09-30") in
  let plan =
    Batch.plan ~max_entries:3 ~lock (nov :: sept :: export.entries) |> Or_error.ok_exn
  in
  List.iter plan.batches ~f:(fun b ->
    printf
      "%s: %s\n"
      b.id
      (String.concat ~sep:" " (List.map b.entries ~f:(fun e -> Entry_key.to_string e.key))));
  printf
    "locked: %s\n"
    (String.concat ~sep:" " (List.map plan.locked ~f:(fun e -> Entry_key.to_string e.key)));
  print_s [%sexp (Batch.plan ~max_entries:0 ~lock [] |> Or_error.is_ok : bool)];
  [%expect {|
    2026-10/1: deposit-1:EUR deposit-2:EUR fee-1:EUR
    2026-10/2: fx-9:sell:EUR fx-9:sell:GBP settle-1:EUR
    2026-10/3: scheme-1:EUR
    2026-11/1: early:EUR
    locked: late:EUR
    false
    |}]
;;
