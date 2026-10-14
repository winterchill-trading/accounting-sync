open! Core
open Accounting_sync
open Helpers

let account_ids =
  [ "bank:central"; "fx:settlement"; "customer:1"; "customer:2"; "income:fees"; "clearing:cards" ]
;;

(* A random balanced ledger entry: some legs on random accounts and sides, and one leg
   that balances them. Pending sub-accounts appear too, as holds would book them. *)
let entry_gen i =
  let open Quickcheck.Generator.Let_syntax in
  let%bind currency = Quickcheck.Generator.of_list [ eur; gbp ] in
  let%bind day = Int.gen_incl 1 28 in
  let account_gen =
    let%bind a = Quickcheck.Generator.of_list account_ids in
    let%map pending = Bool.quickcheck_generator in
    let a = id a in
    if pending then Ledger.Account_id.pending a else a
  in
  let%bind legs =
    List.gen_with_length
      2
      (Quickcheck.Generator.tuple3 account_gen Bool.quickcheck_generator (Int.gen_incl 1 50_000))
  in
  let%map last = account_gen in
  let postings =
    List.map legs ~f:(fun (a, debit, minor) ->
      let amt = Money.Amount.of_minor_units_int currency minor in
      if debit then Ledger.Posting.debit a amt else Ledger.Posting.credit a amt)
  in
  let net =
    List.fold postings ~init:(Money.Amount.zero currency) ~f:(fun acc p ->
      Money.Amount.add_exn acc (Ledger.Posting.signed p))
  in
  let postings =
    if Money.Amount.is_zero net
    then postings
    else if Money.Amount.is_positive net
    then postings @ [ Ledger.Posting.credit last net ]
    else postings @ [ Ledger.Posting.debit last (Money.Amount.neg net) ]
  in
  entry ~day (sprintf "tx-%d" i) postings
;;

let journal_gen =
  let open Quickcheck.Generator.Let_syntax in
  let%bind n = Int.gen_incl 0 25 in
  let%map entries =
    Quickcheck.Generator.all (List.init n ~f:entry_gen)
  in
  records (accounts @ List.map entries ~f:(fun e -> Ledger.Record.Event.Posted e))
;;

let sexp_of_journal records =
  [%sexp (List.length records : int)]
;;

let%test_unit "with a complete mapping, exported net per code equals the ledger's" =
  Quickcheck.test journal_gen ~sexp_of:sexp_of_journal ~trials:300 ~f:(fun records ->
    let export = Export.run ~mapping:full_mapping records in
    [%test_result: int] (List.length export.blocked) ~expect:0;
    let tracker, _ = Tracker.stage Tracker.empty export.entries in
    let r =
      Reconciliation.run
        ~mapping:full_mapping
        ~from:(oct 1)
        ~to_:(oct 31)
        records
        tracker
    in
    (* Nothing is posted, so only the posted column may differ from the ledger. *)
    List.iter r.accounts ~f:(fun a ->
      [%test_result: Money.Amount.t] a.exported ~expect:a.ledger))
;;

let%test_unit "every exported entry balances, keys are unique, export is deterministic" =
  Quickcheck.test journal_gen ~sexp_of:sexp_of_journal ~trials:300 ~f:(fun records ->
    let a = Export.run ~mapping records in
    let b = Export.run ~mapping records in
    [%test_result: string list]
      (List.map a.entries ~f:Journal_entry.digest)
      ~expect:(List.map b.entries ~f:Journal_entry.digest);
    let keys = List.map a.entries ~f:(fun e -> e.key) in
    assert (not (List.contains_dup keys ~compare:Entry_key.compare));
    List.iter a.entries ~f:(fun e ->
      let net =
        List.fold e.lines ~init:(Money.Amount.zero e.currency) ~f:(fun acc l ->
          Money.Amount.add_exn acc (Journal_entry.Line.signed l))
      in
      assert (Money.Amount.is_zero net);
      (* Netting leaves at most one line per code and tracking. *)
      assert (
        not
          (List.contains_dup e.lines ~compare:(fun (x : Journal_entry.Line.t) y ->
             [%compare: Account_code.t * Tracking.Assignment.t list]
               (x.account, x.tracking)
               (y.account, y.tracking))));
      (* Stable round trip, with validation on read. *)
      let bytes =
        Bin_prot.Writer.to_string Journal_entry.Stable.V1.bin_writer_t e
      in
      [%test_result: Journal_entry.t]
        (Bin_prot.Reader.of_string Journal_entry.Stable.V1.bin_reader_t bytes)
        ~expect:e))
;;

let%test_unit "batches partition the input: one period each, bounded, locked set aside" =
  let gen =
    Quickcheck.Generator.tuple3 journal_gen (Int.gen_incl 1 5) (Int.gen_incl 0 28)
  in
  Quickcheck.test gen ~sexp_of:[%sexp_of: _ * int * int] ~trials:300 ~f:(fun (records, max_entries, lock_day) ->
    let entries = (Export.run ~mapping:full_mapping records).entries in
    let lock =
      if lock_day = 0 then Period_lock.none else Period_lock.lock_through Period_lock.none (oct lock_day)
    in
    let plan = Batch.plan ~max_entries ~lock entries |> Or_error.ok_exn in
    let out =
      List.concat_map plan.batches ~f:(fun b ->
        assert (List.length b.entries <= max_entries && not (List.is_empty b.entries));
        assert (List.for_all b.entries ~f:(fun e -> Period.contains b.period e.date));
        b.entries)
      @ plan.locked
    in
    let keys l = List.sort (List.map l ~f:(fun (e : Journal_entry.t) -> e.key)) ~compare:Entry_key.compare in
    [%test_result: Entry_key.t list] (keys out) ~expect:(keys entries);
    assert (List.for_all plan.locked ~f:(fun e -> Period_lock.is_locked lock e.date)))
;;

let%test_unit "staging is idempotent and push keys stay unique across retries" =
  Quickcheck.test journal_gen ~sexp_of:sexp_of_journal ~trials:200 ~f:(fun records ->
    let entries = (Export.run ~mapping:full_mapping records).entries in
    let t1, _ = Tracker.stage Tracker.empty entries in
    let t2, staged = Tracker.stage t1 entries in
    [%test_result: Tracker.t] t2 ~expect:t1;
    [%test_result: int] (List.length staged.unchanged) ~expect:(List.length entries);
    (* Reject everything, retry, and collect every push key ever used. *)
    let at = Time_ns.epoch in
    let reject t =
      List.fold (Tracker.to_send t) ~init:t ~f:(fun t (_, (e : Journal_entry.t)) ->
        Tracker.apply t e.key (Rejected { reason = Reason.create Validation_error; remote = None; at })
        |> Or_error.ok_exn)
    in
    let keys1 = List.map (Tracker.to_send t2) ~f:fst in
    let t3, _ = Tracker.retry_rejected (reject t2) in
    let keys2 = List.map (Tracker.to_send t3) ~f:fst in
    assert (not (List.contains_dup (keys1 @ keys2) ~compare:Push_key.compare)))
;;
