open! Core

module Code = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Unmapped_account
        | Unbalanced
        | Unknown_tracking
        | Period_locked
        | Validation_error
      [@@deriving bin_io, sexp, compare, equal, enumerate]
    end
  end

  include Stable.V1

  let to_string t = String.lowercase (Sexp.to_string (sexp_of_t t))

  let of_string_or_error s =
    match List.find all ~f:(fun t -> String.equal (to_string t) s) with
    | Some t -> Ok t
    | None -> Or_error.error_s [%message "unknown rejection reason" s]
  ;;

  let retryable = function
    | Period_locked | Validation_error -> true
    | Unmapped_account | Unbalanced | Unknown_tracking -> false
  ;;
end

module Stable = struct
  module V1 = struct
    type t =
      { code : Code.Stable.V1.t
      ; detail : string
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1

let create ?(detail = "") code = { code; detail }
