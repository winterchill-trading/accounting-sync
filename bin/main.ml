(* Command-line front end: writes an example ledger journal, exports journals through a
   mapping file, and runs a sync against the simulated accounting system. *)

open! Core
open! Async
open Accounting_sync

let id = Ledger.Account_id.of_string
let key = Ledger.Idempotency_key.of_string
let eur s = Money.Amount.of_decimal_string Money.Currency.eur s |> Or_error.ok_exn
let gbp s = Money.Amount.of_decimal_string Money.Currency.gbp s |> Or_error.ok_exn
let code = Account_code.of_string

let day d =
  Time_ns.of_date_ofday
    ~zone:Time_float.Zone.utc
    (Date.create_exn ~y:2026 ~m:Oct ~d)
    (Time_ns.Ofday.of_string "12:00")
;;

(* A month of a small bank's activity: deposits, a fee, an exchange booked as linked
   legs, a card authorisation captured into card clearing, and the scheme settlement. *)
let write_example path =
  let open Or_error.Let_syntax in
  let%bind j = Ledger.Journal.create path in
  let ok r = Or_error.map r ~f:(fun (_ : Ledger.Journal.Append_result.t) -> ()) in
  let open_ ?(tags = []) ?allow_negative s kind =
    ok (Ledger.Journal.open_account j (Ledger.Account.create ?allow_negative ~tags (id s) kind))
  in
  let%bind () = open_ "bank:central" Asset ~allow_negative:true in
  let%bind () = open_ "fx:settlement" Asset ~allow_negative:true in
  let%bind () = open_ "customer:1" Liability ~tags:[ "segment", "retail" ] in
  let%bind () = open_ "customer:2" Liability ~tags:[ "segment", "business" ] in
  let%bind () = open_ "income:fees" Income in
  let%bind () = open_ "clearing:cards" Asset ~allow_negative:true in
  let transfer ?reference ?tag k d postings =
    ok
      (Ledger.Journal.transfer
         j
         ~idempotency_key:(key k)
         ?tag
         ?reference
         ~effective_at:(day d)
         postings)
  in
  let open Ledger.Posting in
  let%bind () =
    transfer "deposit-1" 1 ~reference:"SEPA in 77"
      [ debit (id "bank:central") (eur "500.00"); credit (id "customer:1") (eur "500.00") ]
  in
  let%bind () =
    transfer "deposit-2" 2 ~tag:"deposit"
      [ debit (id "bank:central") (eur "1200.00"); credit (id "customer:2") (eur "1200.00") ]
  in
  let%bind () =
    transfer "fee-1" 3 ~tag:"monthly fee"
      [ debit (id "customer:1") (eur "2.50"); credit (id "income:fees") (eur "2.50") ]
  in
  let leg k postings =
    Ledger.Entry.create
      ~idempotency_key:(key k)
      ~kind:(Transfer "exchange")
      ~code:Fx_leg
      ~reference:"FX 9"
      ~effective_at:(day 5)
      ~recorded_at:(Ledger.Journal.now j)
      postings
  in
  let%bind sell =
    leg
      "fx-9:sell"
      [ debit (id "customer:2") (eur "100.00")
      ; credit (id "fx:settlement") (eur "99.50")
      ; credit (id "income:fees") (eur "0.50")
      ]
  in
  let%bind buy =
    leg "fx-9:buy" [ debit (id "fx:settlement") (gbp "85.00"); credit (id "customer:2") (gbp "85.00") ]
  in
  let%bind () = ok (Ledger.Journal.append_linked j [ sell; buy ]) in
  let hold_id = Ledger.Hold_id.of_string "auth-1" in
  let%bind () =
    ok
      (Ledger.Journal.hold
         j
         ~hold_id
         ~account:(id "customer:1")
         ~amount:(eur "20.00")
         ~idempotency_key:(key "auth-1")
         ~effective_at:(day 7)
         ())
  in
  let%bind () =
    ok
      (Ledger.Journal.capture
         j
         ~hold_id
         ~to_:(id "clearing:cards")
         ~idempotency_key:(key "settle-1")
         ~effective_at:(day 8)
         ())
  in
  let%map () =
    transfer "scheme-1" 9
      [ debit (id "clearing:cards") (eur "20.00"); credit (id "bank:central") (eur "20.00") ]
  in
  Ledger.Journal.close j
;;

let example_mapping =
  Mapping.create_exn
    ~tracking:[ "segment", "Cost centre" ]
    [ Account (id "bank:central"), code "1000"
    ; Prefix "fx:", code "1100"
    ; Prefix "customer:", code "2000"
    ; Account (id "clearing:cards"), code "2100"
    ; Class Income, code "4000"
    ]
;;

let read_records path =
  Ledger.Journal.read path |> Or_error.map ~f:(fun (records, _tail) -> records)
;;

let read_mapping path =
  Or_error.try_with (fun () -> Sexp.load_sexp_conv_exn path Mapping.Stable.V1.t_of_sexp)
;;

let date_flag name ~doc =
  Command.Param.flag name (Command.Param.optional Command.Param.date) ~doc
;;

let basis_flag =
  let%map_open.Command business =
    flag "-business-date" no_arg ~doc:" date entries by the ledger business date"
  in
  if business then Export.Date_basis.Business_date else Value_date
;;

let print_entry (e : Journal_entry.t) =
  printf
    "%s  %s  %s  %s\n"
    (Entry_key.to_string e.key)
    (Date.to_string e.date)
    (Money.Currency.to_string e.currency)
    e.narration;
  List.iter e.lines ~f:(fun l ->
    printf
      "  %s %-6s %12s%s\n"
      (match l.side with
       | Debit -> "Dr"
       | Credit -> "Cr")
      (Account_code.to_string l.account)
      (Money.Amount.to_decimal_string l.amount)
      (String.concat
         (List.map l.tracking ~f:(fun t -> sprintf "  %s=%s" t.category t.option))))
;;

let example_command =
  Command.basic
    ~summary:"Write an example ledger journal (a month of a small bank)"
    (let%map_open.Command journal =
       flag "-journal" (required string) ~doc:"FILE journal to create"
     in
     fun () -> Or_error.ok_exn (write_example journal))
;;

let mapping_command =
  Command.basic
    ~summary:"Print a mapping file for the example journal"
    (Command.Param.return (fun () ->
       print_s (Mapping.Stable.V1.sexp_of_t example_mapping)))
;;

let export_command =
  Command.basic_or_error
    ~summary:"Print the journal entries a ledger journal exports to, and what blocks"
    (let%map_open.Command journal = flag "-journal" (required string) ~doc:"FILE ledger journal"
     and mapping = flag "-mapping" (required string) ~doc:"FILE mapping (sexp)"
     and from = date_flag "-from" ~doc:"DATE first day (inclusive)"
     and to_ = date_flag "-to" ~doc:"DATE last day (inclusive)"
     and basis = basis_flag in
     fun () ->
       let open Or_error.Let_syntax in
       let%bind records = read_records journal in
       let%map mapping = read_mapping mapping in
       let export = Export.run ~basis ?from ?to_ ~mapping records in
       List.iter export.entries ~f:print_entry;
       List.iter (Export.unmapped export) ~f:(fun u ->
         printf
           "unmapped %s: %d entries, %s\n"
           (Ledger.Account_id.to_string u.account)
           u.entries
           (String.concat ~sep:", " (List.map u.amounts ~f:Money.Amount.to_string))))
;;

let sync_command =
  Command.async_or_error
    ~summary:
      "Push a journal to a fresh simulated accounting system and reconcile the period"
    (let%map_open.Command journal = flag "-journal" (required string) ~doc:"FILE ledger journal"
     and mapping = flag "-mapping" (required string) ~doc:"FILE mapping (sexp)"
     and from = flag "-from" (required date) ~doc:"DATE first day (inclusive)"
     and to_ = flag "-to" (required date) ~doc:"DATE last day (inclusive)"
     and lock = date_flag "-locked-through" ~doc:"DATE the system's lock date"
     and reject = flag "-reject-next" (optional_with_default 0 int) ~doc:"N reject the next N entries" in
     fun () ->
       let open Deferred.Or_error.Let_syntax in
       let%bind records = Deferred.return (read_records journal) in
       let%bind mapping = Deferred.return (read_mapping mapping) in
       (* The simulated chart holds every code the mapping uses, so only locks and the
          reject hook refuse anything. *)
       let chart =
         Mapping.rules mapping
         |> List.map ~f:snd
         |> List.dedup_and_sort ~compare:Account_code.compare
         |> List.map ~f:(fun c -> Chart.Account.create c ~name:(Account_code.to_string c) Asset)
         |> Chart.create_exn
       in
       let categories =
         List.map (Mapping.tracking_rules mapping) ~f:(fun (tag, category) ->
           let options =
             List.filter_map records ~f:(fun (r : Ledger.Record.t) ->
               match r.event with
               | Account_opened a -> Map.find (Ledger.Account.tags a) tag
               | _ -> None)
             |> List.dedup_and_sort ~compare:String.compare
           in
           { Tracking.Category.name = category; options })
       in
       let sim = Simulated.create ~chart ~categories () in
       let organisation = { Organisation.id = "org-1"; name = "Example Ltd" } in
       Option.iter lock ~f:(fun d ->
         Simulated.set_period_lock
           sim
           organisation
           (Period_lock.lock_through Period_lock.none d));
       Simulated.reject_next sim ~count:reject Validation_error;
       let export = Export.run ~from ~to_ ~mapping records in
       let now = Time_ns.of_date_ofday ~zone:Time_float.Zone.utc to_ Time_ns.Ofday.start_of_day in
       let%map tracker, run =
         Sync.push
           (Simulated.connector sim)
           organisation
           Tracker.empty
           ~entries:export.entries
           ~now
       in
       List.iter (Simulated.entries sim organisation) ~f:(fun e ->
         printf
           "%s %-20s %s\n"
           e.number
           (Push_key.to_string e.push_key)
           (match e.state with
            | Posted -> "posted"
            | Received -> "received"
            | Voided -> "voided"
            | Rejected r -> "rejected " ^ Reason.Code.to_string r.code));
       List.iter run.refused_locally ~f:(fun (k, r) ->
         printf "refused %s: %s\n" (Entry_key.to_string k) (Reason.Code.to_string r.code));
       let r = Reconciliation.run ~mapping ~from ~to_ records tracker in
       printf
         "entries %d posted %d rejected %d blocked %d reconciled %b\n"
         r.entries
         r.matched
         r.rejected
         r.blocked
         (Reconciliation.reconciled r))
;;

let () =
  Command.group
    ~summary:"Export ledger journals to accounting systems"
    [ "example", example_command
    ; "mapping-example", mapping_command
    ; "export", export_command
    ; "sync", sync_command
    ]
  |> Command_unix.run
;;
