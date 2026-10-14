open! Core

module Account_type = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Asset
        | Bank
        | Liability
        | Equity
        | Revenue
        | Expense
      [@@deriving bin_io, sexp, compare, equal, enumerate, quickcheck]
    end
  end

  include Stable.V1

  let to_string t = String.lowercase (Sexp.to_string (sexp_of_t t))

  let of_string_or_error s =
    match List.find all ~f:(fun t -> String.equal (to_string t) (String.lowercase s)) with
    | Some t -> Ok t
    | None -> Or_error.error_s [%message "unknown account type" s]
  ;;
end

module Account = struct
  module Stable = struct
    module V1 = struct
      type t =
        { code : Account_code.Stable.V1.t
        ; name : string
        ; type_ : Account_type.Stable.V1.t
        ; active : bool
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1

  let create ?(active = true) code ~name type_ = { code; name; type_; active }
end

module Repr = struct
  type t = Account.Stable.V1.t list [@@deriving bin_io, sexp, compare, equal]
end

type t = Account.t Account_code.Map.t

let accounts t = Map.data t
let compare a b = Repr.compare (accounts a) (accounts b)
let equal a b = Repr.equal (accounts a) (accounts b)
let sexp_of_t t = Repr.sexp_of_t (accounts t)

let create (accounts : Account.t list) =
  match List.find accounts ~f:(fun a -> String.is_empty (String.strip a.name)) with
  | Some a ->
    Or_error.error_s
      [%message "chart account without a name" ~code:(a.code : Account_code.t)]
  | None ->
    (match Account_code.Map.of_alist (List.map accounts ~f:(fun a -> a.code, a)) with
     | `Ok t -> Ok t
     | `Duplicate_key code ->
       Or_error.error_s [%message "duplicate account code" (code : Account_code.t)])
;;

let create_exn accounts = Or_error.ok_exn (create accounts)
let t_of_sexp sexp = create_exn (Repr.t_of_sexp sexp)
let find t code = Map.find t code

let accepts t code =
  match find t code with
  | Some (a : Account.t) -> a.active
  | None -> false
;;

module Stable = struct
  module V1 = struct
    type nonrec t = t

    let compare = compare
    let equal = equal
    let sexp_of_t = sexp_of_t
    let t_of_sexp = t_of_sexp

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Repr)
        (struct
          type nonrec t = t

          let to_binable = accounts
          let of_binable = create_exn
        end)
  end
end
