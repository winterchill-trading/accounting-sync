open! Core
open Accounting_sync
open Helpers

let at = Time_ns.epoch

(* Marks every entry posted without a remote system: the tracker is a plain value. *)
let post_all tracker =
  List.fold (Tracker.to_send tracker) ~init:tracker ~f:(fun t (pk, (e : Journal_entry.t)) ->
    Tracker.apply
      t
      e.key
      (Posted
         { remote = Remote_id.of_string ("r-" ^ Push_key.to_string pk)
         ; number = ""
         ; at
         })
    |> Or_error.ok_exn)
;;

let print r =
  let r : Reconciliation.t = r in
  printf
    "entries %d matched %d not_pushed %d pending %d rejected %d changed %d extra %d \
     blocked %d -> %b\n"
    r.entries
    r.matched
    r.not_pushed
    r.pending
    r.rejected
    r.changed
    r.extra
    r.blocked
    (Reconciliation.reconciled r);
  List.iter r.currencies ~f:(fun c ->
    printf
      "  %s exported %s (%d lines) posted %s (%d lines)\n"
      (Money.Currency.to_string c.currency)
      (Money.Amount.to_decimal_string c.exported_debits)
      c.exported_lines
      (Money.Amount.to_decimal_string c.posted_debits)
      c.posted_lines);
  List.iter r.accounts ~f:(fun a ->
    printf
      "  %s %-8s ledger %8s exported %8s posted %8s\n"
      (Money.Currency.to_string a.currency)
      (Option.value_map a.account ~default:"(none)" ~f:Account_code.to_string)
      (Money.Amount.to_decimal_string a.ledger)
      (Money.Amount.to_decimal_string a.exported)
      (Money.Amount.to_decimal_string a.posted))
;;

let recon ?all ?(mapping = full_mapping) tracker =
  Reconciliation.run ?all ~mapping ~from:(oct 1) ~to_:(oct 31) october tracker
;;

let%expect_test "nothing pushed, everything pushed, a period with blocked entries" =
  print (recon Tracker.empty);
  let tracker, _ = Tracker.stage Tracker.empty (Export.run ~mapping:full_mapping october).entries in
  let tracker = post_all tracker in
  print (recon tracker);
  print (recon ~all:true tracker);
  print (recon ~mapping tracker);
  [%expect {|
    entries 7 matched 0 not_pushed 7 pending 0 rejected 0 changed 0 extra 0 blocked 0 -> false
      EUR exported 1842.50 (13 lines) posted 0.00 (0 lines)
      GBP exported 85.00 (2 lines) posted 0.00 (0 lines)
      EUR 1000     ledger  1680.00 exported  1680.00 posted     0.00
      EUR 1100     ledger   -99.50 exported   -99.50 posted     0.00
      EUR 2000     ledger -1577.50 exported -1577.50 posted     0.00
      EUR 4000     ledger    -3.00 exported    -3.00 posted     0.00
      GBP 1100     ledger    85.00 exported    85.00 posted     0.00
      GBP 2000     ledger   -85.00 exported   -85.00 posted     0.00
    entries 7 matched 7 not_pushed 0 pending 0 rejected 0 changed 0 extra 0 blocked 0 -> true
      EUR exported 1842.50 (13 lines) posted 1842.50 (13 lines)
      GBP exported 85.00 (2 lines) posted 85.00 (2 lines)
    entries 7 matched 7 not_pushed 0 pending 0 rejected 0 changed 0 extra 0 blocked 0 -> true
      EUR exported 1842.50 (13 lines) posted 1842.50 (13 lines)
      GBP exported 85.00 (2 lines) posted 85.00 (2 lines)
      EUR 1000     ledger  1680.00 exported  1680.00 posted  1680.00
      EUR 1100     ledger   -99.50 exported   -99.50 posted   -99.50
      EUR 2000     ledger -1577.50 exported -1577.50 posted -1577.50
      EUR 2100     ledger     0.00 exported     0.00 posted     0.00
      EUR 4000     ledger    -3.00 exported    -3.00 posted    -3.00
      GBP 1100     ledger    85.00 exported    85.00 posted    85.00
      GBP 2000     ledger   -85.00 exported   -85.00 posted   -85.00
    entries 5 matched 5 not_pushed 0 pending 0 rejected 0 changed 0 extra 2 blocked 2 -> false
      EUR exported 1802.50 (9 lines) posted 1842.50 (13 lines)
      GBP exported 85.00 (2 lines) posted 85.00 (2 lines)
      EUR 1000     ledger  1680.00 exported  1700.00 posted  1680.00
      EUR 2000     ledger -1577.50 exported -1597.50 posted -1577.50
    |}]
;;

let%expect_test "an entry posted but no longer exported is extra" =
  let tracker, _ = Tracker.stage Tracker.empty (Export.run ~mapping:full_mapping october).entries in
  let tracker = post_all tracker in
  let fewer =
    List.filter october ~f:(fun r ->
      not
        (List.exists (Ledger.Record.entries r) ~f:(fun e ->
           String.equal (Ledger.Idempotency_key.to_string e.idempotency_key) "fee-1")))
  in
  print (Reconciliation.run ~mapping:full_mapping ~from:(oct 1) ~to_:(oct 31) fewer tracker);
  [%expect {|
    entries 6 matched 6 not_pushed 0 pending 0 rejected 0 changed 0 extra 1 blocked 0 -> false
      EUR exported 1840.00 (11 lines) posted 1842.50 (13 lines)
      GBP exported 85.00 (2 lines) posted 85.00 (2 lines)
      EUR 2000     ledger -1580.00 exported -1580.00 posted -1577.50
      EUR 4000     ledger    -0.50 exported    -0.50 posted    -3.00
    |}]
;;
