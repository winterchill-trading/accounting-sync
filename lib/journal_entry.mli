(** A journal entry as an external accounting system takes it, independent of any one
    system's API.

    One entry is in one currency, dated by a calendar day, with lines on the system's
    account codes. The optional [fx] rate turns the entry currency into the books'
    reporting currency for systems that store both; systems that compute their own rate
    ignore it. Lines carry the ledger accounts they came from ([sources]) so a rejection
    can be traced back. *)

open! Core

module Line : sig
  type t =
    { account : Account_code.t
    ; side : Ledger.Side.t
    ; amount : Money.Amount.t (** always positive; the side carries the direction *)
    ; description : string
    ; tracking : Tracking.Assignment.t list
    ; sources : Ledger.Account_id.t list (** ledger accounts netted into this line *)
    }
  [@@deriving sexp, compare, equal]

  (** [amount] for a debit, minus [amount] for a credit. *)
  val signed : t -> Money.Amount.t

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

type t = private
  { key : Entry_key.t
  ; transaction : Ledger.Idempotency_key.t (** the ledger transaction it exports *)
  ; date : Date.t
  ; currency : Money.Currency.t
  ; fx : Money.Rate.t option (** [currency] to the reporting currency *)
  ; narration : string
  ; reference : string
  ; lines : Line.t list
  }
[@@deriving sexp_of, compare, equal]

(** Longest narration accepted; longer text is cut by {!create}. Most systems store at
    least this much. *)
val max_narration : int

(** Fails unless there are at least two lines, every amount is positive and in
    [currency], debits equal credits, and [fx] (when given) has [currency] as its base. *)
val create
  :  key:Entry_key.t
  -> transaction:Ledger.Idempotency_key.t
  -> date:Date.t
  -> currency:Money.Currency.t
  -> ?fx:Money.Rate.t
  -> ?narration:string (** default [""] *)
  -> ?reference:string (** default [""] *)
  -> Line.t list
  -> t Or_error.t

(** Sum of the debit lines, which equals the sum of the credit lines. *)
val total : t -> Money.Amount.t

(** A short hex fingerprint of the entry's content. Two exports of an unchanged ledger
    transaction under an unchanged mapping have the same digest; anything that would
    change what the remote system stores changes it. *)
val digest : t -> string

module Stable : sig
  module V1 : sig
    (** Decoding validates again. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
