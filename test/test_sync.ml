open! Core
open Accounting_sync
open Helpers

let now = Time_ns.of_string_with_utc_offset "2026-11-02T03:00:00Z"
let acme = { Organisation.id = "org-1"; name = "Acme Ltd" }
let acme_eu = { Organisation.id = "org-2"; name = "Acme EU" }
let run f = Async.Thread_safe.block_on_async_exn f
let ok = Or_error.ok_exn

let print_run (r : Sync.Run.t) =
  printf
    "added %d unchanged %d changed %d | refused locally %d | batches %s | sent %d \
     accepted %d posted %d rejected %d\n"
    (List.length r.staged.added)
    (List.length r.staged.unchanged)
    (List.length r.staged.changed_after_send)
    (List.length r.refused_locally)
    (String.concat ~sep:"," r.batches)
    r.sent
    r.accepted
    r.posted
    r.rejected
;;

let print_remote sim org =
  List.iter (Simulated.entries sim org) ~f:(fun e ->
    printf
      "  %s %s %-22s %s\n"
      (Remote_id.to_string e.id)
      e.number
      (Push_key.to_string e.push_key)
      (Sexp.to_string [%sexp (e.state : Simulated.Remote_entry.state)]))
;;

let print_tracker tracker =
  List.iter (Tracker.items tracker) ~f:(fun i ->
    printf
      "  %-14s attempt %d %s%s\n"
      (Entry_key.to_string i.entry.key)
      i.attempt
      (Status.name i.status)
      (match i.status with
       | Rejected { reason; _ } -> " " ^ Reason.Code.to_string reason.code
       | _ -> ""))
;;

let%expect_test "connect, push, repeat, reject and retry, change and void" =
  run (fun () ->
    let open Async_kernel in
    let sim = Simulated.create ~chart ~categories () in
    let c = Simulated.connector sim in
    (* Consent: the URL carries the state; the grant comes back with organisations. *)
    let conn = Connection.start ~state:"st-81" ~at:now |> ok in
    let%bind url =
      Connector.authorization_url c ~state:"st-81" ~organisation_name:"Acme Ltd"
    in
    print_endline (ok url);
    let%bind before = Connector.complete_authorization c ~state:"st-81" in
    print_s [%sexp (before : Organisation.t list Or_error.t)];
    ok (Simulated.grant sim ~state:"st-81" ~organisations:[ acme; acme_eu ]);
    let%bind granted = Connector.complete_authorization c ~state:"st-81" >>| ok in
    let conn = Connection.select conn ~state:"st-81" ~granted ~organisation:acme ~at:now |> ok in
    print_s [%sexp (Connection.name conn : string)];
    let%bind again = Connector.complete_authorization c ~state:"st-81" in
    print_s [%sexp (again : Organisation.t list Or_error.t)];
    (* First sync: two transactions are blocked by the mapping, five go out. *)
    let export = Export.run ~mapping october in
    let%bind tracker, r =
      Sync.push ~max_entries:3 c acme Tracker.empty ~entries:export.entries ~now >>| ok
    in
    print_run r;
    (* The same export again sends nothing. *)
    let%bind tracker, r = Sync.push c acme tracker ~entries:export.entries ~now >>| ok in
    print_run r;
    (* The mapping is completed; the system rejects the next entry. *)
    Simulated.reject_next sim ~count:1 Period_locked;
    let export = Export.run ~mapping:full_mapping october in
    let%bind tracker, r = Sync.push c acme tracker ~entries:export.entries ~now >>| ok in
    print_run r;
    print_tracker tracker;
    let tracker, moved = Tracker.retry_rejected tracker in
    print_s [%sexp (moved : Entry_key.t list)];
    let%bind tracker, r = Sync.push c acme tracker ~entries:export.entries ~now >>| ok in
    print_run r;
    print_remote sim acme;
    print_s
      [%sexp
        (Reconciliation.reconciled
           (Reconciliation.run
              ~mapping:full_mapping
              ~from:(oct 1)
              ~to_:(oct 31)
              october
              tracker)
         : bool)];
    (* Tracking is dropped from the mapping: posted entries change. *)
    let untracked = Mapping.create_exn (Mapping.rules full_mapping) in
    let export = Export.run ~mapping:untracked october in
    let%bind tracker, r = Sync.push c acme tracker ~entries:export.entries ~now >>| ok in
    print_run r;
    let recon =
      Reconciliation.run ~mapping:untracked ~from:(oct 1) ~to_:(oct 31) october tracker
    in
    printf "changed %d reconciled %b\n" recon.changed (Reconciliation.reconciled recon);
    let%bind tracker =
      Sync.void
        ~retry:true
        c
        acme
        tracker
        (Entry_key.of_string "deposit-1:EUR")
        ~note:"tracking removed"
        ~now
      >>| ok
    in
    let%bind tracker, r = Sync.push c acme tracker ~entries:export.entries ~now >>| ok in
    print_run r;
    print_remote sim acme;
    print_tracker tracker;
    (* After disconnecting, the organisation refuses every call. *)
    let%bind () = Connector.disconnect c acme >>| ok in
    let conn = Connection.disconnect conn ~at:now |> ok in
    print_s [%sexp (Connection.name conn : string)];
    let%map r = Sync.push c acme tracker ~entries:export.entries ~now in
    print_s [%sexp (Result.is_error r : bool)]);
  [%expect {|
    simulated://simulated/consent?state=st-81&organisation=Acme+Ltd
    (Ok ())
    connected
    (Error "consent already exchanged")
    added 5 unchanged 0 changed 0 | refused locally 0 | batches 2026-10/1,2026-10/2 | sent 5 accepted 0 posted 5 rejected 0
    added 0 unchanged 5 changed 0 | refused locally 0 | batches  | sent 0 accepted 0 posted 0 rejected 0
    added 2 unchanged 5 changed 0 | refused locally 0 | batches 2026-10/1 | sent 2 accepted 0 posted 1 rejected 1
      deposit-1:EUR  attempt 1 posted
      deposit-2:EUR  attempt 1 posted
      fee-1:EUR      attempt 1 posted
      fx-9:sell:EUR  attempt 1 posted
      fx-9:sell:GBP  attempt 1 posted
      scheme-1:EUR   attempt 1 posted
      settle-1:EUR   attempt 1 rejected period_locked
    (settle-1:EUR)
    added 0 unchanged 7 changed 0 | refused locally 0 | batches 2026-10/1 | sent 1 accepted 0 posted 1 rejected 0
      je_000001 JE-0001 deposit-1:EUR:1        Posted
      je_000002 JE-0002 deposit-2:EUR:1        Posted
      je_000003 JE-0003 fee-1:EUR:1            Posted
      je_000004 JE-0004 fx-9:sell:EUR:1        Posted
      je_000005 JE-0005 fx-9:sell:GBP:1        Posted
      je_000006 JE-0006 settle-1:EUR:1         (Rejected((code Period_locked)(detail"rejected by test hook")))
      je_000007 JE-0007 scheme-1:EUR:1         Posted
      je_000008 JE-0008 settle-1:EUR:2         Posted
    true
    added 0 unchanged 1 changed 6 | refused locally 0 | batches  | sent 0 accepted 0 posted 0 rejected 0
    changed 6 reconciled false
    added 0 unchanged 2 changed 5 | refused locally 0 | batches 2026-10/1 | sent 1 accepted 0 posted 1 rejected 0
      je_000001 JE-0001 deposit-1:EUR:1        Voided
      je_000002 JE-0002 deposit-2:EUR:1        Posted
      je_000003 JE-0003 fee-1:EUR:1            Posted
      je_000004 JE-0004 fx-9:sell:EUR:1        Posted
      je_000005 JE-0005 fx-9:sell:GBP:1        Posted
      je_000006 JE-0006 settle-1:EUR:1         (Rejected((code Period_locked)(detail"rejected by test hook")))
      je_000007 JE-0007 scheme-1:EUR:1         Posted
      je_000008 JE-0008 settle-1:EUR:2         Posted
      je_000009 JE-0009 deposit-1:EUR:2        Posted
      deposit-1:EUR  attempt 2 posted
      deposit-2:EUR  attempt 1 posted
      fee-1:EUR      attempt 1 posted
      fx-9:sell:EUR  attempt 1 posted
      fx-9:sell:GBP  attempt 1 posted
      scheme-1:EUR   attempt 1 posted
      settle-1:EUR   attempt 2 posted
    disconnected
    true
    |}]
;;

let%expect_test "a remote lock refuses entries before sending; polling decides" =
  run (fun () ->
    let open Async_kernel in
    let sim = Simulated.create ~decide_on_poll:true ~number_prefix:"MJ" ~chart ~categories () in
    let c = Simulated.connector sim in
    Simulated.set_period_lock
      sim
      acme
      (Period_lock.lock_through Period_lock.none (oct 4));
    let export = Export.run ~mapping:full_mapping october in
    let%bind tracker, r = Sync.push c acme Tracker.empty ~entries:export.entries ~now >>| ok in
    print_run r;
    print_tracker tracker;
    let%bind tracker, p = Sync.poll c acme tracker ~now >>| ok in
    print_s [%sexp (p : Sync.Poll.t)];
    print_remote sim acme;
    print_s [%sexp (Tracker.counts tracker : (string * int) list)];
    (* Without the local check, the system itself refuses an archived code. *)
    let bad =
      Journal_entry.create
        ~key:(Entry_key.of_string "x:EUR")
        ~transaction:(key "x")
        ~date:(oct 20)
        ~currency:eur
        [ { account = code "9999"; side = Debit; amount = amount "5.00 EUR"; description = ""; tracking = []; sources = [] }
        ; { account = code "4000"; side = Credit; amount = amount "5.00 EUR"; description = ""; tracking = [ { category = "Cost centre"; option = "ops" } ]; sources = [] }
        ]
      |> ok
    in
    let%bind tracker, _ = Sync.push ~check:false c acme tracker ~entries:[ bad ] ~now >>| ok in
    let%map tracker, _ = Sync.poll c acme tracker ~now >>| ok in
    print_s
      [%sexp
        (Option.map (Tracker.find tracker bad.key) ~f:(fun i -> i.status) : Status.t option)]);
  [%expect {|
    added 7 unchanged 0 changed 0 | refused locally 3 | batches 2026-10/1 | sent 4 accepted 4 posted 0 rejected 0
      deposit-1:EUR  attempt 1 rejected period_locked
      deposit-2:EUR  attempt 1 rejected period_locked
      fee-1:EUR      attempt 1 rejected period_locked
      fx-9:sell:EUR  attempt 1 submitted
      fx-9:sell:GBP  attempt 1 submitted
      scheme-1:EUR   attempt 1 submitted
      settle-1:EUR   attempt 1 submitted
    ((asked 4) (posted 4) (rejected 0) (still_open 0))
      mj_000001 MJ-0001 fx-9:sell:EUR:1        Posted
      mj_000002 MJ-0002 fx-9:sell:GBP:1        Posted
      mj_000003 MJ-0003 settle-1:EUR:1         Posted
      mj_000004 MJ-0004 scheme-1:EUR:1         Posted
    ((pending 0) (submitted 0) (posted 4) (rejected 3) (voided 0))
    ((Rejected (reason ((code Unmapped_account) (detail "line 1 (9999)")))
      (remote (mj_000005)) (at "2026-11-02 03:00:00Z")))
    |}]
;;
