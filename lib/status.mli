(** Where one exported entry stands in the remote system.

    {v
      Pending --accepted--> Submitted --posted--> Posted --voided--> Voided
         |                     |                                       |
         +------posted---------|-------------------> Posted            |
         +------rejected-------+---rejected--> Rejected --retry--> Pending
         +------voided-----------------------> Voided   --retry--> Pending
    v}

    [Pending] is exported but not known to the remote system yet. [Submitted] means the
    system accepted the entry and will decide later (some systems queue manual journals).
    [Posted] is booked remotely; the only way out is a void, which reverses it there.
    [Rejected] carries the reason; a retry starts a new attempt. Repeating an answer that
    is already recorded (the same remote id posted twice) is accepted and changes nothing,
    because status polls overlap. *)

open! Core

type t =
  | Pending
  | Submitted of
      { remote : Remote_id.t
      ; at : Time_ns.Alternate_sexp.t
      }
  | Posted of
      { remote : Remote_id.t
      ; number : string (** the system's human-facing number, e.g. [MJ-0042] *)
      ; at : Time_ns.Alternate_sexp.t
      }
  | Rejected of
      { reason : Reason.t
      ; remote : Remote_id.t option
      ; at : Time_ns.Alternate_sexp.t
      }
  | Voided of
      { remote : Remote_id.t option (** the voided remote entry, if one existed *)
      ; note : string
      ; at : Time_ns.Alternate_sexp.t
      }
[@@deriving sexp, compare, equal]

module Event : sig
  type t =
    | Accepted of
        { remote : Remote_id.t
        ; at : Time_ns.Alternate_sexp.t
        }
    | Posted of
        { remote : Remote_id.t
        ; number : string
        ; at : Time_ns.Alternate_sexp.t
        }
    | Rejected of
        { reason : Reason.t
        ; remote : Remote_id.t option
        ; at : Time_ns.Alternate_sexp.t
        }
    | Voided of
        { note : string
        ; at : Time_ns.Alternate_sexp.t
        }
    | Retry
  [@@deriving sexp, compare, equal]
end

(** The status after [event], or an error for a transition the machine does not allow
    (posting a rejected entry, an answer naming another remote entry, retrying a posted
    one). *)
val apply : t -> Event.t -> t Or_error.t

(** ["pending"], ["submitted"], ["posted"], ["rejected"], ["voided"]. *)
val name : t -> string

(** The remote entry the status refers to, if any. *)
val remote : t -> Remote_id.t option

(** [Pending] or [Submitted]: the remote outcome is not known yet. *)
val is_open : t -> bool

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
