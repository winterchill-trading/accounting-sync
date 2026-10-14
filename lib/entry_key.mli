(** The idempotent id of one exported journal entry.

    A ledger transaction that moves several currencies becomes one external entry per
    currency, so the key is the transaction's ledger idempotency key, a colon and the
    currency: [payment-81:EUR], [swap-7:USDC@polygon]. Exporting the same journal twice
    gives the same keys, which is what lets a sync skip entries it already posted. *)

open! Core

include Text_id.S

(** [create ~transaction currency] is ["<transaction>:<currency>"]. *)
val create : transaction:Ledger.Idempotency_key.t -> Money.Currency.t -> t
