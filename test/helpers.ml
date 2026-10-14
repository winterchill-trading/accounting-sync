open! Core
open Accounting_sync

let eur = Money.Currency.eur
let gbp = Money.Currency.gbp
let amount = Money.Amount.of_string
let id = Ledger.Account_id.of_string
let key = Ledger.Idempotency_key.of_string
let code = Account_code.of_string
let oct day = Date.create_exn ~y:2026 ~m:Oct ~d:day
let debit a s = Ledger.Posting.debit (id a) (amount s)
let credit a s = Ledger.Posting.credit (id a) (amount s)

let noon day =
  Time_ns.of_date_ofday ~zone:Time_float.Zone.utc (oct day) (Time_ns.Ofday.of_string "12:00")
;;

let entry ?reference ?(tag = "transfer") ~day k postings =
  Ledger.Entry.create
    ~idempotency_key:(key k)
    ~kind:(Transfer tag)
    ?reference
    ~effective_at:(noon day)
    ~recorded_at:(noon day)
    postings
  |> Or_error.ok_exn
;;

let records events = List.mapi events ~f:(fun i event -> { Ledger.Record.seq = i + 1; event })

let open_ ?(tags = []) ?allow_negative s kind =
  Ledger.Record.Event.Account_opened (Ledger.Account.create ?allow_negative ~tags (id s) kind)
;;

let accounts =
  [ open_ "bank:central" Asset ~allow_negative:true
  ; open_ "fx:settlement" Asset ~allow_negative:true
  ; open_ "customer:1" Liability ~tags:[ "segment", "retail" ]
  ; open_ "customer:2" Liability ~tags:[ "segment", "business" ]
  ; open_ "income:fees" Income
  ; open_ "clearing:cards" Asset ~allow_negative:true
  ]
;;

let chart =
  Chart.create_exn
    [ Chart.Account.create (code "1000") ~name:"Bank" Bank
    ; Chart.Account.create (code "1100") ~name:"FX clearing" Asset
    ; Chart.Account.create (code "2000") ~name:"Customer deposits" Liability
    ; Chart.Account.create (code "2100") ~name:"Card clearing" Asset
    ; Chart.Account.create (code "4000") ~name:"Fee income" Revenue
    ; Chart.Account.create (code "9999") ~name:"Old suspense" Asset ~active:false
    ]
;;

let categories = [ { Tracking.Category.name = "Cost centre"; options = [ "retail"; "business" ] } ]

let mapping =
  Mapping.create_exn
    ~tracking:[ "segment", "Cost centre" ]
    [ Account (id "bank:central"), code "1000"
    ; Prefix "fx:", code "1100"
    ; Prefix "customer:", code "2000"
    ; Class Income, code "4000"
    ]
;;

let full_mapping = Mapping.set mapping (Account (id "clearing:cards")) (code "2100")

let october =
  let hold_id = Ledger.Hold_id.of_string "auth-1" in
  let pending = Ledger.Account_id.pending (id "customer:1") in
  let hold_entry kind k day postings =
    Ledger.Entry.create
      ~idempotency_key:(key k)
      ~kind
      ~code:Card_auth
      ~effective_at:(noon day)
      ~recorded_at:(noon day)
      postings
    |> Or_error.ok_exn
  in
  records
    (accounts
     @ [ Posted
           (entry
              ~day:1
              ~reference:"SEPA in 77"
              "deposit-1"
              [ debit "bank:central" "500.00 EUR"; credit "customer:1" "500.00 EUR" ])
       ; Posted
           (entry
              ~day:2
              "deposit-2"
              ~tag:"deposit"
              [ debit "bank:central" "1200.00 EUR"; credit "customer:2" "1200.00 EUR" ])
       ; Posted
           (entry
              ~day:3
              ~tag:"monthly fee"
              "fee-1"
              [ debit "customer:1" "2.50 EUR"; credit "income:fees" "2.50 EUR" ])
       ; Linked
           [ entry
               ~day:5
               ~reference:"FX 9"
               "fx-9:sell"
               [ debit "customer:2" "100.00 EUR"
               ; credit "fx:settlement" "99.50 EUR"
               ; credit "income:fees" "0.50 EUR"
               ]
           ; entry
               ~day:5
               "fx-9:buy"
               [ debit "fx:settlement" "85.00 GBP"; credit "customer:2" "85.00 GBP" ]
           ]
       ; Posted
           (hold_entry
              (Hold_place hold_id)
              "auth-1"
              7
              [ Ledger.Posting.debit (id "customer:1") (amount "20.00 EUR")
              ; Ledger.Posting.credit pending (amount "20.00 EUR")
              ])
       ; Posted
           (hold_entry
              (Hold_capture hold_id)
              "settle-1"
              8
              [ Ledger.Posting.debit pending (amount "20.00 EUR")
              ; Ledger.Posting.credit (id "clearing:cards") (amount "20.00 EUR")
              ])
       ; Posted
           (entry
              ~day:9
              "scheme-1"
              [ debit "clearing:cards" "20.00 EUR"; credit "bank:central" "20.00 EUR" ])
       ])
;;

let print_entry (e : Journal_entry.t) =
  printf
    "%s  %s  %s%s  %S\n"
    (Entry_key.to_string e.key)
    (Date.to_string e.date)
    (Money.Currency.to_string e.currency)
    (match e.fx with
     | None -> ""
     | Some r -> " @ " ^ Money.Rate.price_to_string (Money.Rate.price r))
    e.narration;
  List.iter e.lines ~f:(fun l ->
    printf
      "  %-6s %-5s %12s  %s%s\n"
      (match l.side with
       | Debit -> "Dr"
       | Credit -> "Cr")
      (Account_code.to_string l.account)
      (Money.Amount.to_decimal_string l.amount)
      (String.concat ~sep:"," (List.map l.sources ~f:Ledger.Account_id.to_string))
      (match l.tracking with
       | [] -> ""
       | ts ->
         "  ["
         ^ String.concat
             ~sep:"; "
             (List.map ts ~f:(fun (t : Tracking.Assignment.t) ->
                t.category ^ "=" ^ t.option))
         ^ "]"))
;;
