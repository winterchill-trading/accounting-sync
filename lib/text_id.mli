(** Short identifiers checked once, at the edge.

    An id is 1 to [max_length] characters from [A-Z a-z 0-9 _ - . : / @ +]. That covers
    account codes such as [4000] or [1200-EUR], remote entry ids, and entry keys built from
    a ledger idempotency key and a currency code, while keeping every id safe to print in
    a report, a file name or a log line without quoting. *)

open! Core

module type S = sig
  type t [@@deriving quickcheck]

  include Identifiable.S with type t := t

  (** [of_string] raises on an invalid id; this is the non-raising form. *)
  val of_string_or_error : string -> t Or_error.t

  (** The longest id this type accepts. *)
  val max_length : int

  module Stable : sig
    module V1 : sig
      (** Bin_prot is the plain string, so the encoding never changes with the
          validation rules. *)
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
    end
  end
end

(** Why [s] is not a valid id of at most [max_length] characters, if it is not. *)
val check : max_length:int -> string -> unit Or_error.t

(** One fresh id type per use, so account codes and entry keys cannot be mixed up. *)
module Make
    (_ : sig
       (** Used in error messages, e.g. ["Accounting_sync.Account_code"]. *)
       val module_name : string

       val max_length : int
     end)
    () : S
