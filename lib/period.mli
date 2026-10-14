(** An accounting period: one calendar month. *)

open! Core

type t = private
  { year : int
  ; month : Month.t
  }
[@@deriving sexp, compare, equal, hash]

include Comparable.S with type t := t

val create : year:int -> month:Month.t -> t

(** The period containing [date]. *)
val of_date : Date.t -> t

val first_day : t -> Date.t
val last_day : t -> Date.t
val contains : t -> Date.t -> bool
val next : t -> t
val prev : t -> t

(** ["2026-10"]. *)
val to_string : t -> string

(** Parses [to_string]'s form. *)
val of_string_or_error : string -> t Or_error.t

module Stable : sig
  module V1 : sig
    (** Sexp is the text form. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end
