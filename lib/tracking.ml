open! Core

module Category = struct
  module Stable = struct
    module V1 = struct
      type t =
        { name : string
        ; options : string list
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
end

module Assignment = struct
  module Stable = struct
    module V1 = struct
      type t =
        { category : string
        ; option : string
        }
      [@@deriving bin_io, sexp, compare, equal, hash]
    end
  end

  include Stable.V1
  include Comparable.Make (Stable.V1)
end

let check (categories : Category.t list) (assignments : Assignment.t list) =
  let rec go seen = function
    | [] -> Ok ()
    | (a : Assignment.t) :: rest ->
      if Set.mem seen a.category
      then Or_error.error_s [%message "category assigned twice" ~category:a.category]
      else (
        match
          List.find categories ~f:(fun (c : Category.t) -> String.equal c.name a.category)
        with
        | None ->
          Or_error.error_s [%message "unknown tracking category" ~category:a.category]
        | Some c when not (List.mem c.options a.option ~equal:String.equal) ->
          Or_error.error_s
            [%message "unknown tracking option" ~category:a.category ~option:a.option]
        | Some _ -> go (Set.add seen a.category) rest)
  in
  go String.Set.empty assignments
;;
