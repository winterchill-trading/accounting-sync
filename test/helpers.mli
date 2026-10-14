open! Core
open Accounting_sync

val eur : Money.Currency.t
val gbp : Money.Currency.t

(** [amount "12.34 EUR"]. *)
val amount : string -> Money.Amount.t

val id : string -> Ledger.Account_id.t
val key : string -> Ledger.Idempotency_key.t
val code : string -> Account_code.t

(** 2026-10-[day]. *)
val oct : int -> Date.t

val debit : string -> string -> Ledger.Posting.t
val credit : string -> string -> Ledger.Posting.t

(** An entry effective at noon UTC on 2026-10-[day]. *)
val entry
  :  ?reference:string
  -> ?tag:string
  -> day:int
  -> string
  -> Ledger.Posting.t list
  -> Ledger.Entry.t

(** Records numbered from 1. *)
val records : Ledger.Record.Event.t list -> Ledger.Record.t list

(** A small bank: a central bank account, customer accounts (tagged with a cost centre),
    an FX settlement account, fee income and a card clearing account. *)
val accounts : Ledger.Record.Event.t list

(** Codes 1000 bank, 1100 fx clearing, 2000 customer deposits, 2100 card clearing, 4000
    fee income, 9999 archived. *)
val chart : Chart.t

(** One tracking category, [Cost centre], with options [retail] and [business]. *)
val categories : Tracking.Category.t list

(** Maps every account of {!accounts} except the card clearing account. *)
val mapping : Mapping.t

(** The {!mapping} plus the card clearing account. *)
val full_mapping : Mapping.t

(** A month of activity on {!accounts}: deposits, a fee, an exchange as linked entries, a
    card hold placed and captured, and a card settlement through the clearing account. *)
val october : Ledger.Record.t list

val print_entry : Journal_entry.t -> unit
