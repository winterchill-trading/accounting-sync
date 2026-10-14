(** One sync against a connected organisation: stage, check, batch, post, record.

    {!push} stages a fresh export into the tracker, refuses locally what is certain to be
    refused (closed periods, codes missing from the chart, unknown tracking options)
    without sending it, sends the rest in batches and records every answer. A batch whose
    request fails leaves its entries pending under the same push keys, so the next sync
    resends them and the remote system books each at most once. {!poll} asks about entries
    the system accepted but has not decided yet.

    Both return the new tracker value; storing it is the caller's job. *)

open! Async_kernel
open! Core

module Run : sig
  type t =
    { staged : Tracker.Staged.t
    ; refused_locally : (Entry_key.t * Reason.t) list
    ; batches : string list (** ids of the batches sent *)
    ; failed_batches : (string * Error.t) list (** request errors; entries stay pending *)
    ; sent : int
    ; accepted : int (** waiting for a decision *)
    ; posted : int
    ; rejected : int
    }
  [@@deriving sexp_of]
end

(** Stages [entries], refuses what cannot pass, sends the rest and records the answers.
    Fails only when the system's lock, chart or categories cannot be read; a failed batch
    is reported in {!Run.t.failed_batches}. *)
val push
  :  ?max_entries:int (** per batch; see {!Batch.plan} *)
  -> ?lock:Period_lock.t (** local closed periods, combined with the system's *)
  -> ?check:bool (** default [true]: fetch the chart and run {!Check} before sending *)
  -> Connector.t
  -> Organisation.t
  -> Tracker.t
  -> entries:Journal_entry.t list
  -> now:Time_ns.t
  -> (Tracker.t * Run.t) Deferred.Or_error.t

module Poll : sig
  type t =
    { asked : int
    ; posted : int
    ; rejected : int
    ; still_open : int
    }
  [@@deriving sexp_of]
end

(** Asks about every submitted entry and records the decisions. *)
val poll
  :  Connector.t
  -> Organisation.t
  -> Tracker.t
  -> now:Time_ns.t
  -> (Tracker.t * Poll.t) Deferred.Or_error.t

(** Voids the remote entry of a posted entry and records it; with a replacement waiting, a
    later {!Tracker.apply} [Retry] (or [~retry:true] here) queues the new content. *)
val void
  :  ?retry:bool
  -> Connector.t
  -> Organisation.t
  -> Tracker.t
  -> Entry_key.t
  -> note:string
  -> now:Time_ns.t
  -> Tracker.t Deferred.Or_error.t
