open! Core

let entry ~chart ~categories ~lock (entry : Journal_entry.t) =
  let lines = List.mapi entry.lines ~f:(fun i l -> i + 1, l) in
  let net =
    List.fold entry.lines ~init:(Money.Amount.zero entry.currency) ~f:(fun acc l ->
      Money.Amount.add_exn acc (Journal_entry.Line.signed l))
  in
  match
    List.find lines ~f:(fun (_, (l : Journal_entry.Line.t)) ->
      not (Chart.accepts chart l.account))
  with
  | Some (n, l) ->
    Some
      (Reason.create
         Unmapped_account
         ~detail:(sprintf "line %d (%s)" n (Account_code.to_string l.account)))
  | None ->
    if not (Money.Amount.is_zero net)
    then Some (Reason.create Unbalanced)
    else (
      match
        List.find_map lines ~f:(fun (n, l) ->
          match Tracking.check categories l.tracking with
          | Ok () -> None
          | Error e -> Some (sprintf "line %d: %s" n (Error.to_string_hum e)))
      with
      | Some detail -> Some (Reason.create Unknown_tracking ~detail)
      | None ->
        if Period_lock.is_locked lock entry.date
        then Some (Reason.create Period_locked ~detail:(Date.to_string entry.date))
        else None)
;;
