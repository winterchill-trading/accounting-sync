(** The code of an account in an external chart of accounts, e.g. [1200] or [4000-FX].

    At most 64 characters. Codes are compared as text: [090] and [90] are different
    accounts, as they are in most accounting systems. *)

open! Core
include Text_id.S
