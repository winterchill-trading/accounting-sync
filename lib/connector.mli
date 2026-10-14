(** What an accounting system adapter provides.

    One implementation per system (or per API version of one). Adapters for real
    systems live in their own packages, next to their HTTP clients; this library ships
    {!Simulated}. Every operation is asynchronous and may fail with an error for
    transport problems; a refusal of an entry is not an error but an {!Answer.Rejected}.

    Contract an adapter must keep:
    - [post] is idempotent per push key: posting the same key again returns the answer
      for the entry created the first time, never a second entry.
    - [post] answers every key it was given, in any order.
    - [poll] answers only for ids it knows; an id it does not know is left out. *)

open! Async_kernel
open! Core

(** The system's answer about one entry. *)
module Answer : sig
  type t =
    | Accepted of Remote_id.t (** received; the decision comes later through [poll] *)
    | Posted of
        { remote : Remote_id.t
        ; number : string
        }
    | Rejected of
        { remote : Remote_id.t option
        ; reason : Reason.t
        }
  [@@deriving sexp, compare, equal]

  (** The status event recording this answer at [at]. *)
  val to_event : t -> at:Time_ns.t -> Status.Event.t
end

module type S = sig
  type t

  (** A short system name for logs and reports, e.g. ["simulated"]. *)
  val system : t -> string

  (** Where to send the user to grant access. [state] comes back with the grant. *)
  val authorization_url
    :  t
    -> state:string
    -> organisation_name:string
    -> string Deferred.Or_error.t

  (** Exchanges a returned [state] for the organisations the grant covers; empty when
      the user has not granted access (yet). *)
  val complete_authorization : t -> state:string -> Organisation.t list Deferred.Or_error.t

  (** Revokes access to the organisation. Entries already posted stay in the system. *)
  val disconnect : t -> Organisation.t -> unit Deferred.Or_error.t

  (** The organisation's chart of accounts. *)
  val chart : t -> Organisation.t -> Chart.t Deferred.Or_error.t

  (** The organisation's tracking categories and their options. *)
  val tracking_categories : t -> Organisation.t -> Tracking.Category.t list Deferred.Or_error.t

  (** The system's own closed periods, to check entries against before sending. *)
  val period_lock : t -> Organisation.t -> Period_lock.t Deferred.Or_error.t

  (** Sends entries under their push keys; answers each key. *)
  val post
    :  t
    -> Organisation.t
    -> (Push_key.t * Journal_entry.t) list
    -> (Push_key.t * Answer.t) list Deferred.Or_error.t

  (** The current answer for each known remote id. *)
  val poll
    :  t
    -> Organisation.t
    -> Remote_id.t list
    -> (Remote_id.t * Answer.t) list Deferred.Or_error.t

  (** Voids (reverses) a posted entry in the system. *)
  val void : t -> Organisation.t -> Remote_id.t -> unit Deferred.Or_error.t

  (** A link to the entry in the system's own interface, if it has one. *)
  val view_url : t -> Organisation.t -> Remote_id.t -> string option
end

(** A connector of any implementation. *)
type t = T : (module S with type t = 'a) * 'a -> t

(** {2 Dispatch}

    Each function calls the implementation's operation of the same name; see {!S}. *)

(** {!S.system}. *)
val system : t -> string
(** {!S.authorization_url}. *)
val authorization_url : t -> state:string -> organisation_name:string -> string Deferred.Or_error.t
(** {!S.complete_authorization}. *)
val complete_authorization : t -> state:string -> Organisation.t list Deferred.Or_error.t
(** {!S.disconnect}. *)
val disconnect : t -> Organisation.t -> unit Deferred.Or_error.t
(** {!S.chart}. *)
val chart : t -> Organisation.t -> Chart.t Deferred.Or_error.t
(** {!S.tracking_categories}. *)
val tracking_categories : t -> Organisation.t -> Tracking.Category.t list Deferred.Or_error.t
(** {!S.period_lock}. *)
val period_lock : t -> Organisation.t -> Period_lock.t Deferred.Or_error.t

(** {!S.post}. *)
val post
  :  t
  -> Organisation.t
  -> (Push_key.t * Journal_entry.t) list
  -> (Push_key.t * Answer.t) list Deferred.Or_error.t

(** {!S.poll}. *)
val poll
  :  t
  -> Organisation.t
  -> Remote_id.t list
  -> (Remote_id.t * Answer.t) list Deferred.Or_error.t

(** {!S.void}. *)
val void : t -> Organisation.t -> Remote_id.t -> unit Deferred.Or_error.t
(** {!S.view_url}. *)
val view_url : t -> Organisation.t -> Remote_id.t -> string option
