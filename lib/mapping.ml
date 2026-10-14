open! Core

module Rule = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Account of Ledger.Account_id.Stable.V1.t
        | Prefix of string
        | Tag of
            { key : string
            ; value : string
            }
        | Class of Ledger.Account_kind.Stable.V1.t
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
end

module Problem = struct
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

module Repr = struct
  type t =
    { rules : (Rule.Stable.V1.t * Account_code.Stable.V1.t) list
    ; tracking : (string * string) list
    }
  [@@deriving bin_io, sexp, compare, equal]
end

include Repr

let empty = { rules = []; tracking = [] }

let validate t =
  match List.find_a_dup t.rules ~compare:(fun (a, _) (b, _) -> Rule.compare a b) with
  | None -> Ok t
  | Some (rule, _) -> Or_error.error_s [%message "rule mapped twice" (rule : Rule.t)]
;;

let create ?(tracking = []) rules = validate { rules; tracking }
let create_exn ?tracking rules = Or_error.ok_exn (create ?tracking rules)
let rules t = t.rules
let tracking_rules t = t.tracking

let remove t rule =
  { t with rules = List.filter t.rules ~f:(fun (r, _) -> not (Rule.equal r rule)) }
;;

let set t rule code =
  let t' = remove t rule in
  { t' with rules = t'.rules @ [ rule, code ] }
;;

let tag_value (account : Ledger.Account.t option) key =
  Option.bind account ~f:(fun a -> Map.find (Ledger.Account.tags a) key)
;;

let resolve t id ~account =
  let id = Option.value (Ledger.Account_id.parent_of_pending id) ~default:id in
  let ids = Ledger.Account_id.to_string id in
  let exact =
    List.find_map t.rules ~f:(function
      | Account a, code when Ledger.Account_id.equal a id -> Some code
      | _ -> None)
  in
  let prefix () =
    List.filter_map t.rules ~f:(function
      | Prefix p, code when String.is_prefix ids ~prefix:p -> Some (String.length p, code)
      | _ -> None)
    (* Longest prefix wins; the stable sort keeps the earlier rule on a tie. *)
    |> List.stable_sort ~compare:(fun (a, _) (b, _) -> Int.compare b a)
    |> List.hd
    |> Option.map ~f:snd
  in
  let tag () =
    List.find_map t.rules ~f:(function
      | Tag { key; value }, code ->
        (match tag_value account key with
         | Some v when String.equal v value -> Some code
         | _ -> None)
      | _ -> None)
  in
  let class_ () =
    Option.bind account ~f:(fun a ->
      List.find_map t.rules ~f:(function
        | Class k, code when Ledger.Account_kind.equal k (Ledger.Account.kind a) ->
          Some code
        | _ -> None))
  in
  match exact with
  | Some _ -> exact
  | None -> Option.first_some (prefix ()) (Option.first_some (tag ()) (class_ ()))
;;

let tracking t ~account =
  List.filter_map t.tracking ~f:(fun (key, category) ->
    Option.map (tag_value account key) ~f:(fun option ->
      { Tracking.Assignment.category; option }))
;;

let check t ~chart ~categories =
  let codes =
    List.filter_map t.rules ~f:(fun (rule, code) ->
      match Chart.find chart code with
      | None -> Some (Problem.Unknown_code { rule; code })
      | Some a when not a.active -> Some (Archived_code { rule; code })
      | Some _ -> None)
  in
  let cats =
    List.filter_map t.tracking ~f:(fun (_, category) ->
      if List.exists categories ~f:(fun (c : Tracking.Category.t) ->
           String.equal c.name category)
      then None
      else Some (Problem.Unknown_category { category }))
  in
  codes @ cats
;;

module Stable = struct
  module V1 = struct
    include Repr

    let t_of_sexp sexp = Or_error.ok_exn (validate (Repr.t_of_sexp sexp))

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Repr)
        (struct
          type t = Repr.t

          let to_binable = Fn.id
          let of_binable t = Or_error.ok_exn (validate t)
        end)
  end
end
