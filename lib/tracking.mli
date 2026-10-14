(** Tracking categories: the second dimension of an accounting line, next to its account.

    Systems call them tracking categories, classes, departments, cost centres or
    dimensions. A category has a name ([Cost centre]) and a set of options ([Sales],
    [Engineering]); a line carries at most one option per category. *)

open! Core

module Category : sig
  type t =
    { name : string
    ; options : string list
    }
  [@@deriving sexp, compare, equal]

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

(** One option of one category on a line. *)
module Assignment : sig
  type t =
    { category : string
    ; option : string
    }
  [@@deriving sexp, compare, equal, hash]

  include Comparable.S with type t := t

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
    end
  end
end

(** Fails when a category is unknown, an option is not one of its category's options, or
    two assignments name the same category. *)
val check : Category.t list -> Assignment.t list -> unit Or_error.t
