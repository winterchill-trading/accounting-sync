(** An external system's chart of accounts, as retrieved from it.

    Accounting systems differ in how finely they type accounts; the classes here are the
    ones every common system can map onto, with [Bank] kept apart from [Asset] because
    many systems refuse manual journals against bank accounts or treat them specially. *)

open! Core

module Account_type : sig
  type t =
    | Asset
    | Bank
    | Liability
    | Equity
    | Revenue
    | Expense
  [@@deriving sexp, compare, equal, enumerate, quickcheck]

  (** ["asset"], ["bank"], ... *)
  val to_string : t -> string

  (** Parses [to_string]'s form, ignoring case. *)
  val of_string_or_error : string -> t Or_error.t

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

(** One account of the chart. An archived account ([active = false]) still exists in the
    remote system's history but accepts no new lines. *)
module Account : sig
  type t =
    { code : Account_code.t
    ; name : string
    ; type_ : Account_type.t
    ; active : bool
    }
  [@@deriving sexp, compare, equal]

  (** An active account. *)
  val create : ?active:bool -> Account_code.t -> name:string -> Account_type.t -> t

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

type t [@@deriving sexp, compare, equal]

(** Fails on a duplicate code or an empty name. *)
val create : Account.t list -> t Or_error.t

(** [create] that raises. *)
val create_exn : Account.t list -> t

(** Accounts in code order. *)
val accounts : t -> Account.t list

(** The account with [code], active or archived. *)
val find : t -> Account_code.t -> Account.t option

(** Whether [code] exists and is active. *)
val accepts : t -> Account_code.t -> bool

module Stable : sig
  module V1 : sig
    (** Bin_prot is the account list; reading validates like {!create}. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
