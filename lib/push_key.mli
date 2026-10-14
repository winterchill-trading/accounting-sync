(** The idempotency key sent with one attempt to post an entry.

    [<entry key>:<attempt>], attempts counted from 1. A remote system that has seen the
    key returns the entry it created the first time instead of creating another; a new
    attempt after a rejection or a void gets a new key, so the remote system treats it as
    a new entry. *)

open! Core
include Text_id.S

(** Fails unless [attempt >= 1]. *)
val create : Entry_key.t -> attempt:int -> t Or_error.t

(** [create] that raises. *)
val create_exn : Entry_key.t -> attempt:int -> t
