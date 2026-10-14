open! Core

module Date_basis = struct
  type t =
    | Value_date
    | Business_date
  [@@deriving sexp, compare, equal]
end

module Transaction = struct
  type t =
    { key : Ledger.Idempotency_key.t
    ; seq : int
    ; entries : Ledger.Entry.t list
    }
  [@@deriving sexp_of]

  let of_records records =
    List.filter_map records ~f:(fun (r : Ledger.Record.t) ->
      match Ledger.Record.entries r with
      | [] -> None
      | first :: _ as entries -> Some { key = first.idempotency_key; seq = r.seq; entries })
  ;;

  let date basis t =
    let (first : Ledger.Entry.t) = List.hd_exn t.entries in
    match (basis : Date_basis.t) with
    | Business_date -> first.business_date
    | Value_date -> Time_ns.to_date first.effective_at ~zone:Time_float.Zone.utc
  ;;
end

module Blocked = struct
  type t =
    { key : Entry_key.t
    ; date : Date.t
    ; unmapped : (Ledger.Account_id.t * Money.Amount.t) list
    }
  [@@deriving sexp_of, compare, equal]
end

module Unmapped = struct
  type t =
    { account : Ledger.Account_id.t
    ; entries : int
    ; amounts : Money.Amount.t list
    }
  [@@deriving sexp_of, compare, equal]
end

type t =
  { entries : Journal_entry.t list
  ; blocked : Blocked.t list
  ; netted_out : Entry_key.t list
  }
[@@deriving sexp_of]

let default_narration (tx : Transaction.t) =
  let (first : Ledger.Entry.t) = List.hd_exn tx.entries in
  let tag =
    match first.kind with
    | Transfer tag -> tag
    | _ -> ""
  in
  List.find
    [ first.reference; first.remittance_info; tag ]
    ~f:(Fn.non String.is_empty)
  |> Option.value ~default:(Ledger.Entry.Code.to_string first.code)
;;

let parent id = Option.value (Ledger.Account_id.parent_of_pending id) ~default:id

(* One currency of one transaction. Postings are netted per (code, tracking); the
   sources of a line are the ledger accounts that fed it. *)
let export_currency ~mapping ~accounts ~key ~date ~narration ~reference ~fx ~tx currency
  postings
  =
  let account id = Map.find accounts (parent id) in
  let lines = Hashtbl.Poly.create () in
  let unmapped = Ledger.Account_id.Table.create () in
  List.iter postings ~f:(fun (p : Ledger.Posting.t) ->
    let acct = account p.account in
    match Mapping.resolve mapping p.account ~account:acct with
    | None ->
      Hashtbl.update unmapped (parent p.account) ~f:(function
        | None -> p.amount
        | Some a -> Money.Amount.add_exn a p.amount)
    | Some code ->
      let tracking = Mapping.tracking mapping ~account:acct in
      Hashtbl.update lines (code, tracking) ~f:(fun prev ->
        let net, sources = Option.value prev ~default:(Money.Amount.zero currency, []) in
        ( Money.Amount.add_exn net (Ledger.Posting.signed p)
        , parent p.account :: sources )));
  if not (Hashtbl.is_empty unmapped)
  then
    `Blocked
      { Blocked.key
      ; date
      ; unmapped =
          Hashtbl.to_alist unmapped
          |> List.sort ~compare:(fun (a, _) (b, _) -> Ledger.Account_id.compare a b)
      }
  else (
    let lines =
      Hashtbl.to_alist lines
      |> List.filter_map ~f:(fun ((code, tracking), (net, sources)) ->
        if Money.Amount.is_zero net
        then None
        else
          Some
            { Journal_entry.Line.account = code
            ; side = (if Money.Amount.is_positive net then Debit else Credit)
            ; amount = Money.Amount.abs net
            ; description = narration
            ; tracking
            ; sources = List.dedup_and_sort sources ~compare:Ledger.Account_id.compare
            })
      (* Debits first, then by code: a stable, readable order for the remote system. *)
      |> List.sort ~compare:(fun (a : Journal_entry.Line.t) b ->
        Comparable.lift
          [%compare: Ledger.Side.t * Account_code.t * Tracking.Assignment.t list]
          ~f:(fun (l : Journal_entry.Line.t) -> l.side, l.account, l.tracking)
          a
          b)
    in
    match lines with
    | [] -> `Netted_out key
    | lines ->
      `Entry
        (Journal_entry.create
           ~key
           ~transaction:tx
           ~date
           ~currency
           ?fx:(fx currency date)
           ~narration
           ~reference
           lines
         (* Netting a balanced set of postings keeps it balanced, so this cannot fail. *)
         |> Or_error.ok_exn))
;;

let run
  ?(basis = Date_basis.Value_date)
  ?from
  ?to_
  ?touching
  ?(narration = default_narration)
  ?(fx = fun _ _ -> None)
  ~mapping
  records
  =
  let accounts =
    List.fold records ~init:Ledger.Account_id.Map.empty ~f:(fun acc (r : Ledger.Record.t) ->
      match r.event with
      | Account_opened a -> Map.set acc ~key:(Ledger.Account.id a) ~data:a
      | _ -> acc)
  in
  let in_range d =
    Option.for_all from ~f:(fun f -> Date.( >= ) d f)
    && Option.for_all to_ ~f:(fun t -> Date.( <= ) d t)
  in
  let touches (tx : Transaction.t) =
    match touching with
    | None -> true
    | Some f ->
      List.exists tx.entries ~f:(fun (e : Ledger.Entry.t) ->
        List.exists e.postings ~f:(fun p -> f (parent p.account)))
  in
  let results =
    Transaction.of_records records
    |> List.filter ~f:(fun tx -> in_range (Transaction.date basis tx) && touches tx)
    |> List.concat_map ~f:(fun (tx : Transaction.t) ->
      let date = Transaction.date basis tx in
      let narration = narration tx in
      let reference = (List.hd_exn tx.entries).reference in
      let by_currency =
        List.concat_map tx.entries ~f:(fun e ->
          List.map e.postings ~f:(fun p -> Ledger.Entry.currency e, p))
        |> Money.Currency.Map.of_alist_multi
      in
      Map.to_alist by_currency
      |> List.map ~f:(fun (currency, postings) ->
        export_currency
          ~mapping
          ~accounts
          ~key:(Entry_key.create ~transaction:tx.key currency)
          ~date
          ~narration
          ~reference
          ~fx
          ~tx:tx.key
          currency
          postings))
  in
  { entries = List.filter_map results ~f:(function `Entry e -> Some e | _ -> None)
  ; blocked = List.filter_map results ~f:(function `Blocked b -> Some b | _ -> None)
  ; netted_out =
      List.filter_map results ~f:(function `Netted_out k -> Some k | _ -> None)
  }
;;

let unmapped t =
  List.concat_map t.blocked ~f:(fun b -> b.unmapped)
  |> Ledger.Account_id.Map.of_alist_multi
  |> Map.to_alist
  |> List.map ~f:(fun (account, amounts) ->
    { Unmapped.account
    ; entries =
        List.count t.blocked ~f:(fun b ->
          List.exists b.unmapped ~f:(fun (a, _) -> Ledger.Account_id.equal a account))
    ; amounts =
        List.map amounts ~f:(fun a -> Money.Amount.currency a, a)
        |> Money.Currency.Map.of_alist_reduce ~f:Money.Amount.add_exn
        |> Map.data
    })
  |> List.stable_sort ~compare:(fun (a : Unmapped.t) b -> Int.compare b.entries a.entries)
;;
