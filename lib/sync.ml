open! Async_kernel
open! Core

module Run = struct
  type t =
    { staged : Tracker.Staged.t
    ; refused_locally : (Entry_key.t * Reason.t) list
    ; batches : string list
    ; failed_batches : (string * Error.t) list
    ; sent : int
    ; accepted : int
    ; posted : int
    ; rejected : int
    }
  [@@deriving sexp_of]
end

module Poll = struct
  type t =
    { asked : int
    ; posted : int
    ; rejected : int
    ; still_open : int
    }
  [@@deriving sexp_of]
end

let push
  ?max_entries
  ?(lock = Period_lock.none)
  ?(check = true)
  connector
  organisation
  tracker
  ~entries
  ~now
  =
  let open Deferred.Or_error.Let_syntax in
  let tracker, staged = Tracker.stage tracker entries in
  let%bind remote_lock = Connector.period_lock connector organisation in
  let lock = Period_lock.union lock remote_lock in
  let%bind chart_and_categories =
    if check
    then (
      let%bind chart = Connector.chart connector organisation in
      let%map categories = Connector.tracking_categories connector organisation in
      Some (chart, categories))
    else return None
  in
  let refusal (entry : Journal_entry.t) =
    match chart_and_categories with
    | Some (chart, categories) -> Check.entry ~chart ~categories ~lock entry
    | None ->
      if Period_lock.is_locked lock entry.date
      then Some (Reason.create Period_locked ~detail:(Date.to_string entry.date))
      else None
  in
  let to_send = Tracker.to_send tracker in
  let refused, sendable =
    List.partition_map to_send ~f:(fun (push_key, entry) ->
      match refusal entry with
      | Some reason -> First (entry.key, reason)
      | None -> Second (push_key, entry))
  in
  let tracker =
    List.fold refused ~init:tracker ~f:(fun tracker (key, reason) ->
      Or_error.ok_exn
        (Tracker.apply tracker key (Rejected { reason; remote = None; at = now })))
  in
  let push_keys =
    Push_key.Map.of_alist_exn
      (List.map sendable ~f:(fun (push_key, (e : Journal_entry.t)) -> push_key, e.key))
  in
  let%bind plan =
    Deferred.return
      (Batch.plan ?max_entries ~lock:Period_lock.none (List.map sendable ~f:snd))
  in
  let by_entry =
    Entry_key.Map.of_alist_exn
      (List.map sendable ~f:(fun (push_key, (e : Journal_entry.t)) -> e.key, push_key))
  in
  let%map.Deferred tracker, failed, answers =
    Deferred.List.fold
      plan.batches
      ~init:(tracker, [], [])
      ~f:(fun (tracker, failed, answers) (batch : Batch.t) ->
        let request =
          List.map batch.entries ~f:(fun (e : Journal_entry.t) -> Map.find_exn by_entry e.key, e)
        in
        match%map.Deferred Connector.post connector organisation request with
        | Error e -> tracker, (batch.id, e) :: failed, answers
        | Ok replies ->
          let tracker =
            List.fold replies ~init:tracker ~f:(fun tracker (push_key, answer) ->
              match Map.find push_keys push_key with
              | None -> tracker (* not ours: a connector bug, ignored rather than fatal *)
              | Some key ->
                (match
                   Tracker.apply tracker key (Connector.Answer.to_event answer ~at:now)
                 with
                 | Ok tracker -> tracker
                 | Error _ -> tracker))
          in
          tracker, failed, List.map replies ~f:snd @ answers)
  in
  let count f = List.count answers ~f in
  Ok
    ( tracker
    , { Run.staged
      ; refused_locally = refused
      ; batches = List.map plan.batches ~f:(fun b -> b.id)
      ; failed_batches = List.rev failed
      ; sent = List.length answers
      ; accepted =
          count (function
            | Accepted _ -> true
            | _ -> false)
      ; posted =
          count (function
            | Posted _ -> true
            | _ -> false)
      ; rejected =
          count (function
            | Rejected _ -> true
            | _ -> false)
      } )
;;

let poll connector organisation tracker ~now =
  let open Deferred.Or_error.Let_syntax in
  let waiting =
    Tracker.items tracker
    |> List.filter_map ~f:(fun (i : Tracker.Item.t) ->
      match i.status with
      | Submitted { remote; _ } -> Some (remote, i.entry.key)
      | _ -> None)
  in
  let%map answers = Connector.poll connector organisation (List.map waiting ~f:fst) in
  let keys = Remote_id.Map.of_alist_reduce waiting ~f:Fn.const in
  let tracker =
    List.fold answers ~init:tracker ~f:(fun tracker (remote, answer) ->
      match Map.find keys remote with
      | None -> tracker
      | Some key ->
        Option.value
          (Tracker.apply tracker key (Connector.Answer.to_event answer ~at:now)
           |> Result.ok)
          ~default:tracker)
  in
  let open_after =
    List.count waiting ~f:(fun (_, key) ->
      Option.exists (Tracker.find tracker key) ~f:(fun i -> Status.is_open i.status))
  in
  ( tracker
  , { Poll.asked = List.length waiting
    ; posted =
        List.count answers ~f:(fun (_, a) ->
          match a with
          | Posted _ -> true
          | _ -> false)
    ; rejected =
        List.count answers ~f:(fun (_, a) ->
          match a with
          | Rejected _ -> true
          | _ -> false)
    ; still_open = open_after
    } )
;;

let void ?(retry = false) connector organisation tracker key ~note ~now =
  let open Deferred.Or_error.Let_syntax in
  match Tracker.find tracker key with
  | None -> Deferred.Or_error.error_s [%message "unknown entry" (key : Entry_key.t)]
  | Some item ->
    let%bind () =
      match item.status with
      | Posted { remote; _ } -> Connector.void connector organisation remote
      | _ -> return ()
    in
    let%bind tracker =
      Deferred.return (Tracker.apply tracker key (Voided { note; at = now }))
    in
    if retry then Deferred.return (Tracker.apply tracker key Retry) else return tracker
;;
