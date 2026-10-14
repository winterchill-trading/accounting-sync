(** The status of every exported entry for one connection, as a value.

    A sync stages the entries of a fresh export ({!stage}), sends the ones that are
    {!Status.Pending} under their current {!Push_key}, and records each answer
    ({!apply}). A pending entry keeps its push key until it gets an answer, so a request
    that timed out is resent under the same key and the remote system cannot book it
    twice; a retry after a rejection or a void moves to the next attempt and so to a
    new key.

    When the ledger side of an entry changes after it was sent (a mapping change, a
    late reversal booked under the same transaction is a different key and does not
    count), the new content is kept as a [replacement]: it is not sent on its own, since
    the remote entry must be voided first; after the void, a retry sends the
    replacement. *)

open! Core

module Item : sig
  type t =
    { entry : Journal_entry.t (** the content the current attempt sends or sent *)
    ; status : Status.t
    ; attempt : int (** from 1 *)
    ; replacement : Journal_entry.t option
    (** newer content waiting for the sent entry to be voided *)
    }
  [@@deriving sexp_of, compare, equal]

  val push_key : t -> Push_key.t

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

type t [@@deriving sexp_of, compare, equal]

val empty : t
val find : t -> Entry_key.t -> Item.t option

(** In key order. *)
val items : t -> Item.t list

(** What {!stage} did with each entry. *)
module Staged : sig
  type t =
    { added : Entry_key.t list
    ; updated : Entry_key.t list (** new content for an entry not yet accepted remotely *)
    ; unchanged : Entry_key.t list
    ; changed_after_send : Entry_key.t list
    (** new content for a submitted or posted entry, kept as its replacement *)
    }
  [@@deriving sexp_of, compare, equal]
end

(** Adds new entries as pending and compares known ones by {!Journal_entry.digest}. *)
val stage : t -> Journal_entry.t list -> t * Staged.t

(** Pending entries with their push keys, in key order. *)
val to_send : t -> (Push_key.t * Journal_entry.t) list

(** Records an answer or a decision for one entry. A [Retry] moves to the next attempt
    and swaps in the replacement, if any. Fails for an unknown key or a transition
    {!Status.apply} refuses. *)
val apply : t -> Entry_key.t -> Status.Event.t -> t Or_error.t

(** Moves every rejected entry whose reason is retryable (or every rejected entry, with
    [~all:true]) back to pending under a new attempt. Returns the keys moved. *)
val retry_rejected : ?all:bool -> t -> t * Entry_key.t list

(** Entries per status name, every status listed. *)
val counts : t -> (string * int) list

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
