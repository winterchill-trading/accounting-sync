(** An organisation (company, tenant, realm) inside an accounting system, as the system
    names it. A consent may cover several; the user picks one per connection. *)

open! Core

type t =
  { id : string (** the system's id for it *)
  ; name : string
  }
[@@deriving sexp, compare, equal]

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
