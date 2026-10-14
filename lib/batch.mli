(** Groups entries for sending: one period per batch, a bounded number of entries per
    batch, and nothing from a locked period.

    Systems limit how many entries one request may carry, and a sync that fails half way
    should leave whole periods either done or not started where possible, so batches never
    mix periods. Entries are ordered by date, then key, which makes the batches of the
    same input identical between runs. *)

open! Core

type t =
  { id : string (** [<period>/<n>], n counted from 1 within the period *)
  ; period : Period.t
  ; entries : Journal_entry.t list
  }
[@@deriving sexp_of]

type plan =
  { batches : t list (** in period order *)
  ; locked : Journal_entry.t list (** dated inside a locked period; not sent *)
  }
[@@deriving sexp_of]

(** Default 100. *)
val default_max_entries : int

(** Fails unless [max_entries >= 1]. *)
val plan
  :  ?max_entries:int
  -> lock:Period_lock.t
  -> Journal_entry.t list
  -> plan Or_error.t
