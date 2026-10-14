(** Closed accounting periods: nothing dated inside them may be posted.

    Systems express this as a lock date (everything on or before it is closed) and
    sometimes as individually closed months; both are kept here, and a date is locked
    when either rule closes it. A local check refuses locked entries before they are
    sent, with {!Reason.Code.Period_locked}, so a closed month is never touched even
    when the remote system's own lock was not configured. *)

open! Core

type t =
  { through : Date.t option (** everything on or before this day is closed *)
  ; periods : Period.Set.t (** further closed months *)
  }
[@@deriving sexp, compare, equal]

(** Nothing locked. *)
val none : t

val is_locked : t -> Date.t -> bool

(** Moves the lock date; a lock date never moves backwards here. Reopening needs
    {!reopen_through}, so that it is a deliberate act. *)
val lock_through : t -> Date.t -> t

val reopen_through : t -> Date.t option -> t
val lock_period : t -> Period.t -> t

(** Locked when either is: the later lock date and both sets of months. *)
val union : t -> t -> t
val unlock_period : t -> Period.t -> t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
