(** Which external account each ledger account books to, and which tracking options its
    lines carry.

    Rules are tried from the most specific to the least: an exact account id, then the
    longest matching id prefix, then the first matching account tag, then the account's
    class (asset, liability, ...). A ledger hold's pending sub-account ([<id>/pending])
    maps like its parent account, so placing and releasing a hold nets out on the
    external side.

    Tracking comes from account tags: a [(tag_key, category)] pair puts every line from
    an account tagged [tag_key=v] under option [v] of [category]. *)

open! Core

module Rule : sig
  type t =
    | Account of Ledger.Account_id.t (** this account only *)
    | Prefix of string (** every account id starting with the string *)
    | Tag of
        { key : string
        ; value : string
        } (** accounts carrying this tag *)
    | Class of Ledger.Account_kind.t (** every account of this class *)
  [@@deriving sexp, compare, equal]

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

(** Something wrong with a mapping, found by {!check} before any entry is built. *)
module Problem : sig
  type t =
    | Unknown_code of
        { rule : Rule.t
        ; code : Account_code.t
        }
    | Archived_code of
        { rule : Rule.t
        ; code : Account_code.t
        }
    | Unknown_category of { category : string }
  [@@deriving sexp, compare, equal]
end

type t [@@deriving sexp, compare, equal]

val empty : t

(** Fails when one rule appears twice. *)
val create
  :  ?tracking:(string * string) list (** [(tag_key, category)] pairs *)
  -> (Rule.t * Account_code.t) list
  -> t Or_error.t

val create_exn : ?tracking:(string * string) list -> (Rule.t * Account_code.t) list -> t
val rules : t -> (Rule.t * Account_code.t) list
val tracking_rules : t -> (string * string) list

(** Adds the rule or replaces its code. *)
val set : t -> Rule.t -> Account_code.t -> t

val remove : t -> Rule.t -> t

(** The code for a ledger account. [account] is the account as opened in the ledger, if
    known (tag and class rules need it); for a pending sub-account pass the parent's.
    Pending sub-account ids are resolved through their parent before matching. *)
val resolve : t -> Ledger.Account_id.t -> account:Ledger.Account.t option -> Account_code.t option

(** The tracking options for lines from [account], in the order of the tracking rules. *)
val tracking : t -> account:Ledger.Account.t option -> Tracking.Assignment.t list

(** Codes missing from the chart or archived in it, and tracking rules naming unknown
    categories. Empty for a mapping that can be used against this chart. *)
val check : t -> chart:Chart.t -> categories:Tracking.Category.t list -> Problem.t list

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
