open! Core
open Accounting_sync

let id = Ledger.Account_id.of_string
let code = Account_code.of_string
let eur s = Money.Amount.of_string (s ^ " EUR")
let at = Time_ns.of_string_with_utc_offset "2026-10-05T12:00:00Z"

(* Ledger records, as a journal file or a database projection would return them. *)
let records =
  let opened a = Ledger.Record.Event.Account_opened a in
  let fee =
    Ledger.Entry.create
      ~idempotency_key:(Ledger.Idempotency_key.of_string "fee-1")
      ~kind:(Transfer "monthly fee")
      ~effective_at:at
      ~recorded_at:at
      [ Ledger.Posting.debit (id "customer:1") (eur "2.50")
      ; Ledger.Posting.credit (id "income:fees") (eur "2.50")
      ]
    |> Or_error.ok_exn
  in
  List.mapi
    [ opened (Ledger.Account.create (id "customer:1") Liability)
    ; opened (Ledger.Account.create (id "income:fees") Income)
    ; Posted fee
    ]
    ~f:(fun i event -> { Ledger.Record.seq = i + 1; event })
;;

let () =
  let chart =
    Chart.create_exn
      [ Chart.Account.create (code "2000") ~name:"Customer deposits" Liability
      ; Chart.Account.create (code "4000") ~name:"Fee income" Revenue
      ]
  in
  let mapping =
    Mapping.create_exn [ Prefix "customer:", code "2000"; Class Income, code "4000" ]
  in
  assert (List.is_empty (Mapping.check mapping ~chart ~categories:[]));
  let export = Export.run ~mapping records in
  let sim = Simulated.create ~chart ~categories:[] () in
  let org = { Organisation.id = "org-1"; name = "Example Ltd" } in
  let tracker, run =
    Async.Thread_safe.block_on_async_exn (fun () ->
      Sync.push
        (Simulated.connector sim)
        org
        Tracker.empty
        ~entries:export.entries
        ~now:at)
    |> Or_error.ok_exn
  in
  let recon =
    Reconciliation.run
      ~mapping
      ~from:(Date.of_string "2026-10-01")
      ~to_:(Date.of_string "2026-10-31")
      records
      tracker
  in
  printf
    "exported %d, posted %d, reconciled %b\n"
    (List.length export.entries)
    run.posted
    (Reconciliation.reconciled recon)
;;
