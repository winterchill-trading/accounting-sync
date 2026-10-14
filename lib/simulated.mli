(** A deterministic, in-memory accounting system for tests and demos.

    It behaves like a typical system's manual-journal API: a consent page that issues a
    grant per [state], organisations, a chart of accounts and tracking categories, a
    lock date, idempotent posting by push key with per-organisation entry numbers
    ([JE-0001], ...), status polling and voids. It validates entries in the order real
    systems tend to: account codes (missing or archived: [Unmapped_account], detail
    ["line N (code)"]), balance, tracking options, then the lock date. Test hooks make
    it reject the next entries or decide only when polled. *)

open! Core

type t

(** One entry as the simulated system stores it. *)
module Remote_entry : sig
  type state =
    | Received (** accepted, waiting for a poll to decide *)
    | Posted
    | Rejected of Reason.t
    | Voided
  [@@deriving sexp_of, compare, equal]

  type t =
    { id : Remote_id.t
    ; number : string
    ; push_key : Push_key.t
    ; entry : Journal_entry.t
    ; state : state
    }
  [@@deriving sexp_of, compare, equal]
end

val create
  :  ?system:string (** default ["simulated"] *)
  -> ?number_prefix:string (** default ["JE"] *)
  -> ?decide_on_poll:bool
       (** default [false]: posts answer at once. With [true], posts answer
           [Accepted] and the first poll decides. *)
  -> chart:Chart.t
  -> categories:Tracking.Category.t list
  -> unit
  -> t

(** The user pressing "allow" on the consent page for [state]: the grant covers
    [organisations]. Fails for a state no authorization URL was issued for. *)
val grant : t -> state:string -> organisations:Organisation.t list -> unit Or_error.t

val set_chart : t -> Chart.t -> unit
val set_period_lock : t -> Organisation.t -> Period_lock.t -> unit

(** The next [count] valid entries are rejected with [reason] (a demo of a closed
    period or a flaky validation). *)
val reject_next : t -> count:int -> Reason.Code.t -> unit

(** Everything stored for the organisation, in posting order. *)
val entries : t -> Organisation.t -> Remote_entry.t list

include Connector.S with type t := t

(** [t] as a {!Connector.t}. *)
val connector : t -> Connector.t
