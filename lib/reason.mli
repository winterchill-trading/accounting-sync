(** Why an accounting system (or the local checks before it) refused an entry. *)

open! Core

module Code : sig
  type t =
    | Unmapped_account (** a line's account code is missing from the chart or archived *)
    | Unbalanced (** debits differ from credits *)
    | Unknown_tracking (** a tracking category or option the system does not have *)
    | Period_locked (** the entry's date is inside a closed period *)
    | Validation_error (** anything else the system refused *)
  [@@deriving sexp, compare, equal, enumerate]

  (** ["unmapped_account"], ["period_locked"], ... *)
  val to_string : t -> string

  val of_string_or_error : string -> t Or_error.t

  (** Whether posting the same entry again can succeed without changing it: a period
      can be reopened, a validation error may be transient. The others need a new
      mapping, chart or entry first. *)
  val retryable : t -> bool

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

type t =
  { code : Code.t
  ; detail : string (** free text from the system, e.g. ["line 2 (code 7777)"] *)
  }
[@@deriving sexp, compare, equal]

val create : ?detail:string -> Code.t -> t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
