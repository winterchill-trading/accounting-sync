open! Core

type t =
  { id : string
  ; period : Period.t
  ; entries : Journal_entry.t list
  }
[@@deriving sexp_of]

type plan =
  { batches : t list
  ; locked : Journal_entry.t list
  }
[@@deriving sexp_of]

let default_max_entries = 100

let plan ?(max_entries = default_max_entries) ~lock entries =
  if max_entries < 1
  then Or_error.error_s [%message "max_entries must be at least 1" (max_entries : int)]
  else (
    let entries =
      List.sort entries ~compare:(fun (a : Journal_entry.t) b ->
        [%compare: Date.t * Entry_key.t] (a.date, a.key) (b.date, b.key))
    in
    let locked, open_ =
      List.partition_tf entries ~f:(fun (e : Journal_entry.t) ->
        Period_lock.is_locked lock e.date)
    in
    let batches =
      List.map open_ ~f:(fun (e : Journal_entry.t) -> Period.of_date e.date, e)
      |> Period.Map.of_alist_multi
      |> Map.to_alist
      |> List.concat_map ~f:(fun (period, entries) ->
        List.chunks_of entries ~length:max_entries
        |> List.mapi ~f:(fun i entries ->
          { id = sprintf "%s/%d" (Period.to_string period) (i + 1); period; entries }))
    in
    Ok { batches; locked })
;;
