(** The life of one connection to an accounting system.

    {v
      Pending --select--> Connected --disconnect--> Disconnected
         |
         +--cancel--> Cancelled
    v}

    A connection starts when the user is sent to the system's consent page with a
    one-time [state] value; it is completed by that same value coming back, and by
    choosing one of the organisations the consent covers. Cancelled and disconnected
    connections are final: connecting again starts a new connection, so that the
    entries already posted stay attached to the organisation they were posted to. *)

open! Core

type t =
  | Pending of
      { state : string
      ; started_at : Time_ns.Alternate_sexp.t
      }
  | Connected of
      { organisation : Organisation.t
      ; connected_at : Time_ns.Alternate_sexp.t
      }
  | Disconnected of
      { organisation : Organisation.t
      ; at : Time_ns.Alternate_sexp.t
      }
  | Cancelled of { at : Time_ns.Alternate_sexp.t }
[@@deriving sexp, compare, equal]

(** Fails on an empty [state]. *)
val start : state:string -> at:Time_ns.t -> t Or_error.t

(** Completes a pending connection whose state is [state], with [organisation] chosen
    from [granted] (the organisations the consent covers). Fails on another state value,
    an organisation outside the grant, or a connection that is not pending. *)
val select
  :  t
  -> state:string
  -> granted:Organisation.t list
  -> organisation:Organisation.t
  -> at:Time_ns.t
  -> t Or_error.t

(** Fails unless pending. *)
val cancel : t -> at:Time_ns.t -> t Or_error.t

(** Fails unless connected. *)
val disconnect : t -> at:Time_ns.t -> t Or_error.t

(** The organisation of a connected connection. *)
val connected : t -> Organisation.t option

(** ["pending"], ["connected"], ["disconnected"], ["cancelled"]. *)
val name : t -> string

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
