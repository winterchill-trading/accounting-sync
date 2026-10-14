open! Core

include
  Text_id.Make
    (struct
      let module_name = "Accounting_sync.Entry_key"

      (* A ledger key (128) plus a colon and the longest currency text form, with room
         to spare: a network-tagged token reads like [USDC@polygon]. *)
      let max_length = 200
    end)
    ()

let create ~transaction currency =
  of_string
    (Ledger.Idempotency_key.to_string transaction ^ ":" ^ Money.Currency.to_string currency)
;;
