open! Core

module Repr = struct
  module V1 = struct
    type t =
      { through : Date.Stable.V1.t option
      ; periods : Period.Stable.V1.t list
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

type t =
  { through : Date.t option
  ; periods : Period.Set.t
  }
[@@deriving sexp, compare, equal]

let none = { through = None; periods = Period.Set.empty }

let is_locked t date =
  Option.exists t.through ~f:(fun through -> Date.( <= ) date through)
  || Set.mem t.periods (Period.of_date date)
;;

let lock_through t date =
  match t.through with
  | Some current when Date.( >= ) current date -> t
  | _ -> { t with through = Some date }
;;

let reopen_through t through = { t with through }

let union a b =
  { through = Option.merge a.through b.through ~f:Date.max
  ; periods = Set.union a.periods b.periods
  }
;;

let lock_period t p = { t with periods = Set.add t.periods p }
let unlock_period t p = { t with periods = Set.remove t.periods p }

module Stable = struct
  module V1 = struct
    type nonrec t = t [@@deriving compare, equal]

    let to_repr t = { Repr.V1.through = t.through; periods = Set.to_list t.periods }

    let of_repr (r : Repr.V1.t) =
      { through = r.through; periods = Period.Set.of_list r.periods }
    ;;

    let sexp_of_t t = Repr.V1.sexp_of_t (to_repr t)
    let t_of_sexp s = of_repr (Repr.V1.t_of_sexp s)

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Repr.V1)
        (struct
          type nonrec t = t

          let to_binable = to_repr
          let of_binable = of_repr
        end)
  end
end
