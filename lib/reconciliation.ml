open! Core

module Account_line = struct
  type t =
    { currency : Money.Currency.t
    ; account : Account_code.t option
    ; ledger : Money.Amount.t
    ; exported : Money.Amount.t
    ; posted : Money.Amount.t
    }
  [@@deriving sexp_of, compare, equal]

  let matched t =
    Money.Amount.equal t.ledger t.exported && Money.Amount.equal t.exported t.posted
  ;;
end

module Currency_line = struct
  type t =
    { currency : Money.Currency.t
    ; exported_debits : Money.Amount.t
    ; posted_debits : Money.Amount.t
    ; exported_lines : int
    ; posted_lines : int
    }
  [@@deriving sexp_of, compare, equal]

  let matched t =
    Money.Amount.equal t.exported_debits t.posted_debits
    && t.exported_lines = t.posted_lines
  ;;
end

type t =
  { from : Date.t
  ; to_ : Date.t
  ; entries : int
  ; matched : int
  ; not_pushed : int
  ; pending : int
  ; rejected : int
  ; changed : int
  ; extra : int
  ; blocked : int
  ; currencies : Currency_line.t list
  ; accounts : Account_line.t list
  }
[@@deriving sexp_of]

let reconciled t =
  t.not_pushed = 0
  && t.pending = 0
  && t.rejected = 0
  && t.changed = 0
  && t.extra = 0
  && t.blocked = 0
  && List.for_all t.currencies ~f:Currency_line.matched
  && List.for_all t.accounts ~f:Account_line.matched
;;

module Key = struct
  type t = Money.Currency.t * Account_code.t option [@@deriving compare, sexp_of]

  include (val Comparator.make ~compare ~sexp_of_t)
end

let net_of_entries entries =
  List.concat_map entries ~f:(fun (e : Journal_entry.t) ->
    List.map e.lines ~f:(fun l -> (e.currency, Some l.account), Journal_entry.Line.signed l))
;;

let run
  ?(basis = Export.Date_basis.Value_date)
  ?touching
  ?(all = false)
  ~mapping
  ~from
  ~to_
  records
  tracker
  =
  let export = Export.run ~basis ~from ~to_ ?touching ~mapping records in
  let in_range d = Date.( >= ) d from && Date.( <= ) d to_ in
  let exported_keys =
    Entry_key.Set.of_list (List.map export.entries ~f:(fun e -> e.key))
  in
  let classify (e : Journal_entry.t) =
    match Tracker.find tracker e.key with
    | None -> `Not_pushed
    | Some item ->
      (match item.status with
       | Posted _ ->
         if String.equal (Journal_entry.digest item.entry) (Journal_entry.digest e)
         then `Matched
         else `Changed
       | Pending | Submitted _ -> `Pending
       | Rejected _ -> `Rejected
       | Voided _ -> `Not_pushed)
  in
  let classes = List.map export.entries ~f:classify in
  let count c = List.count classes ~f:(fun x -> Poly.equal x c) in
  let posted_entries =
    Tracker.items tracker
    |> List.filter_map ~f:(fun (i : Tracker.Item.t) ->
      match i.status with
      | Posted _ when in_range i.entry.date -> Some i.entry
      | _ -> None)
  in
  let extra =
    List.count posted_entries ~f:(fun e -> not (Set.mem exported_keys e.key))
  in
  (* The ledger view: every posting of the period's transactions, placed by the
     mapping, without netting into entries. *)
  let accounts_by_id =
    List.fold records ~init:Ledger.Account_id.Map.empty ~f:(fun acc (r : Ledger.Record.t) ->
      match r.event with
      | Account_opened a -> Map.set acc ~key:(Ledger.Account.id a) ~data:a
      | _ -> acc)
  in
  let parent id = Option.value (Ledger.Account_id.parent_of_pending id) ~default:id in
  let ledger_net =
    Export.Transaction.of_records records
    |> List.filter ~f:(fun tx ->
      in_range (Export.Transaction.date basis tx)
      && Option.for_all touching ~f:(fun f ->
        List.exists tx.entries ~f:(fun (e : Ledger.Entry.t) ->
          List.exists e.postings ~f:(fun p -> f (parent p.account)))))
    |> List.concat_map ~f:(fun (tx : Export.Transaction.t) ->
      List.concat_map tx.entries ~f:(fun e ->
        List.map e.postings ~f:(fun p ->
          let code =
            Mapping.resolve mapping p.account ~account:(Map.find accounts_by_id (parent p.account))
          in
          (Ledger.Entry.currency e, code), Ledger.Posting.signed p)))
  in
  let sum alist =
    Map.of_alist_reduce (module Key) alist ~f:Money.Amount.add_exn
  in
  let ledger = sum ledger_net in
  let exported = sum (net_of_entries export.entries) in
  let posted = sum (net_of_entries posted_entries) in
  let keys =
    Set.union_list (module Key) (List.map [ ledger; exported; posted ] ~f:Map.key_set)
  in
  let accounts =
    Set.to_list keys
    |> List.map ~f:(fun ((currency, account) as key) ->
      let get m = Option.value (Map.find m key) ~default:(Money.Amount.zero currency) in
      { Account_line.currency
      ; account
      ; ledger = get ledger
      ; exported = get exported
      ; posted = get posted
      })
    |> List.filter ~f:(fun l -> all || not (Account_line.matched l))
  in
  let totals entries =
    List.map entries ~f:(fun (e : Journal_entry.t) ->
      e.currency, (Journal_entry.total e, List.length e.lines))
    |> Money.Currency.Map.of_alist_reduce ~f:(fun (a, n) (b, m) ->
      Money.Amount.add_exn a b, n + m)
  in
  let ex = totals export.entries in
  let po = totals posted_entries in
  let currencies =
    Set.union (Map.key_set ex) (Map.key_set po)
    |> Set.to_list
    |> List.map ~f:(fun currency ->
      let get m =
        Option.value (Map.find m currency) ~default:(Money.Amount.zero currency, 0)
      in
      let exported_debits, exported_lines = get ex in
      let posted_debits, posted_lines = get po in
      { Currency_line.currency
      ; exported_debits
      ; posted_debits
      ; exported_lines
      ; posted_lines
      })
  in
  { from
  ; to_
  ; entries = List.length export.entries
  ; matched = count `Matched
  ; not_pushed = count `Not_pushed
  ; pending = count `Pending
  ; rejected = count `Rejected
  ; changed = count `Changed
  ; extra
  ; blocked = List.length export.blocked
  ; currencies
  ; accounts
  }
;;
