(** Turns ledger records into journal entries for an external system.

    A ledger transaction is one booked record: a single entry, an approved adjustment, or
    a group of linked entries booked together (an exchange's legs and its fee). Each
    transaction becomes one journal entry per currency it moves, keyed
    {!Entry_key.create}. Postings to accounts that map to the same code and tracking
    options are netted into one line, so a hold placed and released inside one
    transaction leaves nothing behind, and a transaction that nets to zero everywhere
    produces no entry at all.

    A transaction with a posting the mapping cannot place is not exported; it is
    reported as blocked, with the accounts that need a rule. *)

open! Core

(** Which day an entry is dated. *)
module Date_basis : sig
  type t =
    | Value_date (** the UTC day of the ledger entry's [effective_at] *)
    | Business_date (** the ledger's business date *)
  [@@deriving sexp, compare, equal]
end

module Transaction : sig
  type t =
    { key : Ledger.Idempotency_key.t (** the first entry's key *)
    ; seq : int (** the record's sequence number *)
    ; entries : Ledger.Entry.t list
    }
  [@@deriving sexp_of]

  (** Booked transactions in journal order; refusals, account events and proposals that
      were never approved book nothing and are skipped. *)
  val of_records : Ledger.Record.t list -> t list

  (** The day the transaction is dated on. *)
  val date : Date_basis.t -> t -> Date.t
end

(** A transaction-currency pair that could not be exported. *)
module Blocked : sig
  type t =
    { key : Entry_key.t
    ; date : Date.t
    ; unmapped : (Ledger.Account_id.t * Money.Amount.t) list
    (** each account without a rule, with the gross amount it moved *)
    }
  [@@deriving sexp_of, compare, equal]
end

(** One ledger account that blocked entries, for the "accounts to map" report. *)
module Unmapped : sig
  type t =
    { account : Ledger.Account_id.t
    ; entries : int
    ; amounts : Money.Amount.t list (** gross per currency, in currency order *)
    }
  [@@deriving sexp_of, compare, equal]
end

type t =
  { entries : Journal_entry.t list (** in journal order *)
  ; blocked : Blocked.t list
  ; netted_out : Entry_key.t list (** transactions that net to zero in a currency *)
  }
[@@deriving sexp_of]

(** Exports the transactions of [records] dated in [from, to_] (both inclusive, default
    unbounded). Accounts are those opened in [records]. *)
val run
  :  ?basis:Date_basis.t (** default [Value_date] *)
  -> ?from:Date.t
  -> ?to_:Date.t
  -> ?touching:(Ledger.Account_id.t -> bool)
       (** keep only transactions with a posting to one of these accounts (pending
           sub-accounts count as their parent); every entry of a kept transaction is
           exported. Default: all. *)
  -> ?narration:(Transaction.t -> string)
       (** default: the first non-empty of the first entry's reference, remittance
           information and transfer tag, else the entry's ledger code *)
  -> ?fx:(Money.Currency.t -> Date.t -> Money.Rate.t option)
       (** rate to the reporting currency for an entry's currency and date *)
  -> mapping:Mapping.t
  -> Ledger.Record.t list
  -> t

(** The accounts that blocked entries, most entries first. *)
val unmapped : t -> Unmapped.t list
