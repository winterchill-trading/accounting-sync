open! Core

module Item = struct
  module Stable = struct
    module V1 = struct
      type t =
        { entry : Journal_entry.Stable.V1.t
        ; status : Status.Stable.V1.t
        ; attempt : int
        ; replacement : Journal_entry.Stable.V1.t option
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1

  let push_key t = Push_key.create_exn t.entry.key ~attempt:t.attempt
end

type t = Item.t Entry_key.Map.t

let items t = Map.data t
let compare a b = [%compare: Item.t list] (items a) (items b)
let equal a b = [%equal: Item.t list] (items a) (items b)
let sexp_of_t t = [%sexp_of: Item.t list] (items t)
let empty = Entry_key.Map.empty
let find t key = Map.find t key

module Staged = struct
  type t =
    { added : Entry_key.t list
    ; updated : Entry_key.t list
    ; unchanged : Entry_key.t list
    ; changed_after_send : Entry_key.t list
    }
  [@@deriving sexp_of, compare, equal]
end

let same a b = String.equal (Journal_entry.digest a) (Journal_entry.digest b)

let stage t entries =
  let t, outcomes =
    List.fold_map entries ~init:t ~f:(fun t (entry : Journal_entry.t) ->
      let key = entry.key in
      match Map.find t key with
      | None ->
        ( Map.set t ~key ~data:{ Item.entry; status = Pending; attempt = 1; replacement = None }
        , `Added key )
      | Some (item : Item.t) ->
        (match item.status with
         | Pending | Rejected _ | Voided _ ->
           if same item.entry entry
           then t, `Unchanged key
           else Map.set t ~key ~data:{ item with entry; replacement = None }, `Updated key
         | Submitted _ | Posted _ ->
           if same item.entry entry
           then
             (* The ledger went back to what was sent: drop a stale replacement. *)
             Map.set t ~key ~data:{ item with replacement = None }, `Unchanged key
           else Map.set t ~key ~data:{ item with replacement = Some entry }, `Changed key))
  in
  let pick f = List.filter_map outcomes ~f in
  ( t
  , { Staged.added =
        pick (function
          | `Added k -> Some k
          | _ -> None)
    ; updated =
        pick (function
          | `Updated k -> Some k
          | _ -> None)
    ; unchanged =
        pick (function
          | `Unchanged k -> Some k
          | _ -> None)
    ; changed_after_send =
        pick (function
          | `Changed k -> Some k
          | _ -> None)
    } )
;;

let to_send t =
  Map.data t
  |> List.filter_map ~f:(fun (item : Item.t) ->
    match item.status with
    | Pending -> Some (Item.push_key item, item.entry)
    | _ -> None)
;;

let apply t key (event : Status.Event.t) =
  match Map.find t key with
  | None -> Or_error.error_s [%message "unknown entry" (key : Entry_key.t)]
  | Some (item : Item.t) ->
    Or_error.map (Status.apply item.status event) ~f:(fun status ->
      let item =
        match event with
        | Retry ->
          { Item.entry = Option.value item.replacement ~default:item.entry
          ; status
          ; attempt = item.attempt + 1
          ; replacement = None
          }
        | _ -> { item with status }
      in
      Map.set t ~key ~data:item)
;;

let retry_rejected ?(all = false) t =
  Map.fold t ~init:(t, []) ~f:(fun ~key ~data:(item : Item.t) (t, moved) ->
    match item.status with
    | Rejected { reason; _ } when all || Reason.Code.retryable reason.code ->
      Or_error.ok_exn (apply t key Retry), key :: moved
    | _ -> t, moved)
  |> fun (t, moved) -> t, List.rev moved
;;

let counts t =
  let names = [ "pending"; "submitted"; "posted"; "rejected"; "voided" ] in
  List.map names ~f:(fun name ->
    name, Map.count t ~f:(fun (i : Item.t) -> String.equal (Status.name i.status) name))
;;

module Stable = struct
  module V1 = struct
    type nonrec t = t

    let compare = compare
    let equal = equal

    let of_items items =
      Entry_key.Map.of_alist_exn (List.map items ~f:(fun (i : Item.t) -> i.entry.key, i))
    ;;

    let sexp_of_t t = [%sexp_of: Item.Stable.V1.t list] (items t)
    let t_of_sexp s = of_items ([%of_sexp: Item.Stable.V1.t list] s)

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (struct
          type t = Item.Stable.V1.t list [@@deriving bin_io]
        end)
        (struct
          type nonrec t = t

          let to_binable = items
          let of_binable = of_items
        end)
  end
end
