open! Async_kernel
open! Core

module Remote_entry = struct
  type state =
    | Received
    | Posted
    | Rejected of Reason.t
    | Voided
  [@@deriving sexp_of, compare, equal]

  type t =
    { id : Remote_id.t
    ; number : string
    ; push_key : Push_key.t
    ; entry : Journal_entry.t
    ; state : state
    }
  [@@deriving sexp_of, compare, equal]
end

type organisation_state =
  { mutable entries : Remote_entry.t list (** newest first *)
  ; mutable lock : Period_lock.t
  ; mutable revoked : bool
  }

type consent =
  | Issued
  | Granted of Organisation.t list
  | Exchanged

type t =
  { system : string
  ; number_prefix : string
  ; decide_on_poll : bool
  ; mutable chart : Chart.t
  ; categories : Tracking.Category.t list
  ; consents : (string, consent) Hashtbl.t
  ; organisations : (string, organisation_state) Hashtbl.t
  ; decisions : (string, Remote_entry.state) Hashtbl.t
  (** decided at post time, shown at the first poll when [decide_on_poll] *)
  ; mutable next_id : int
  ; mutable reject_next : int * Reason.Code.t
  }

let create
  ?(system = "simulated")
  ?(number_prefix = "JE")
  ?(decide_on_poll = false)
  ~chart
  ~categories
  ()
  =
  { system
  ; number_prefix
  ; decide_on_poll
  ; chart
  ; categories
  ; consents = Hashtbl.create (module String)
  ; organisations = Hashtbl.create (module String)
  ; decisions = Hashtbl.create (module String)
  ; next_id = 1
  ; reject_next = 0, Period_locked
  }
;;

let org_state t (org : Organisation.t) =
  Hashtbl.find_or_add t.organisations org.id ~default:(fun () ->
    { entries = []; lock = Period_lock.none; revoked = false })
;;

let grant t ~state ~organisations =
  match Hashtbl.find t.consents state with
  | Some (Issued | Granted _) ->
    Hashtbl.set t.consents ~key:state ~data:(Granted organisations);
    List.iter organisations ~f:(fun o -> (org_state t o).revoked <- false);
    Ok ()
  | Some Exchanged -> Or_error.error_string "consent already exchanged"
  | None -> Or_error.error_string "unknown consent state"
;;

let set_chart t chart = t.chart <- chart
let set_period_lock t org lock = (org_state t org).lock <- lock
let reject_next t ~count reason = t.reject_next <- Int.max 0 count, reason
let entries t org = List.rev (org_state t org).entries
let system t = t.system

let authorization_url t ~state ~organisation_name =
  if String.is_empty state
  then Deferred.Or_error.error_string "empty consent state"
  else (
    Hashtbl.set t.consents ~key:state ~data:Issued;
    return
      (Ok
         (sprintf
            "simulated://%s/consent?state=%s&organisation=%s"
            t.system
            state
            (String.map organisation_name ~f:(fun c -> if Char.is_alphanum c then c else '+')))))
;;

let complete_authorization t ~state =
  return
    (match Hashtbl.find t.consents state with
     | None -> Or_error.error_string "unknown consent state"
     | Some Exchanged -> Or_error.error_string "consent already exchanged"
     | Some Issued -> Ok []
     | Some (Granted orgs) ->
       Hashtbl.set t.consents ~key:state ~data:Exchanged;
       Ok orgs)
;;

let with_access t org f =
  let s = org_state t org in
  if s.revoked
  then Deferred.Or_error.error_s [%message "access revoked" ~organisation:org.id]
  else return (Ok (f s))
;;

let disconnect t org =
  (org_state t org).revoked <- true;
  return (Ok ())
;;

let chart t org = with_access t org (fun _ -> t.chart)
let tracking_categories t org = with_access t org (fun _ -> t.categories)
let period_lock t org = with_access t org (fun s -> s.lock)

(* The checks a manual-journal API runs, in its order; the first failure wins. *)
let validate t (s : organisation_state) (entry : Journal_entry.t) =
  let lines = List.mapi entry.lines ~f:(fun i l -> i + 1, l) in
  let net =
    List.fold entry.lines ~init:(Money.Amount.zero entry.currency) ~f:(fun acc l ->
      Money.Amount.add_exn acc (Journal_entry.Line.signed l))
  in
  match
    List.find lines ~f:(fun (_, (l : Journal_entry.Line.t)) ->
      not (Chart.accepts t.chart l.account))
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
          match Tracking.check t.categories l.tracking with
          | Ok () -> None
          | Error e -> Some (sprintf "line %d: %s" n (Error.to_string_hum e)))
      with
      | Some detail -> Some (Reason.create Unknown_tracking ~detail)
      | None ->
        if Period_lock.is_locked s.lock entry.date
        then Some (Reason.create Period_locked ~detail:(Date.to_string entry.date))
        else (
          match t.reject_next with
          | n, reason when n > 0 ->
            t.reject_next <- n - 1, reason;
            Some (Reason.create reason ~detail:"rejected by test hook")
          | _ -> None))
;;

let answer_of (e : Remote_entry.t) : Connector.Answer.t option =
  match e.state with
  | Received -> Some (Accepted e.id)
  | Posted -> Some (Posted { remote = e.id; number = e.number })
  | Rejected reason -> Some (Rejected { remote = Some e.id; reason })
  | Voided -> None
;;

let post_one t s (push_key, (entry : Journal_entry.t)) =
  match
    List.find s.entries ~f:(fun (e : Remote_entry.t) -> Push_key.equal e.push_key push_key)
  with
  | Some e ->
    (* A repeated push key gets the first answer back; nothing new is stored. *)
    ( push_key
    , Option.value
        (answer_of e)
        ~default:
          (Connector.Answer.Rejected
             { remote = Some e.id
             ; reason = Reason.create Validation_error ~detail:"entry was voided"
             }) )
  | None ->
    let id = Remote_id.of_string (sprintf "%s_%06d" (String.lowercase t.number_prefix) t.next_id) in
    t.next_id <- t.next_id + 1;
    let number = sprintf "%s-%04d" t.number_prefix (List.length s.entries + 1) in
    let decision = validate t s entry in
    let state : Remote_entry.state =
      match decision with
      | Some reason -> Rejected reason
      | None -> Posted
    in
    let stored = { Remote_entry.id; number; push_key; entry; state } in
    s.entries <- stored :: s.entries;
    if t.decide_on_poll
    then (
      (* Remember the decision, show [Received] until the first poll. *)
      s.entries
      <- { stored with state = Received } :: List.tl_exn s.entries;
      Hashtbl.set t.decisions ~key:(Remote_id.to_string id) ~data:state;
      push_key, Connector.Answer.Accepted id)
    else push_key, Option.value_exn (answer_of stored)
;;

let post t org entries =
  with_access t org (fun s -> List.map entries ~f:(post_one t s))
;;

let update s id ~f =
  s.entries
  <- List.map s.entries ~f:(fun (e : Remote_entry.t) ->
       if Remote_id.equal e.id id then f e else e)
;;

let poll t org ids =
  with_access t org (fun s ->
    List.filter_map ids ~f:(fun id ->
      Option.iter (Hashtbl.find_and_remove t.decisions (Remote_id.to_string id)) ~f:(fun state ->
        update s id ~f:(fun e -> { e with state }));
      List.find s.entries ~f:(fun (e : Remote_entry.t) -> Remote_id.equal e.id id)
      |> Option.bind ~f:answer_of
      |> Option.map ~f:(fun answer -> id, answer)))
;;

let void t org id =
  let s = org_state t org in
  match List.find s.entries ~f:(fun (e : Remote_entry.t) -> Remote_id.equal e.id id) with
  | _ when s.revoked ->
    Deferred.Or_error.error_s [%message "access revoked" ~organisation:org.id]
  | Some { state = Posted | Voided; _ } ->
    update s id ~f:(fun e -> { e with state = Voided });
    return (Ok ())
  | Some _ -> Deferred.Or_error.error_s [%message "only posted entries can be voided" (id : Remote_id.t)]
  | None -> Deferred.Or_error.error_s [%message "unknown entry" (id : Remote_id.t)]
;;

let view_url t (org : Organisation.t) id =
  Some (sprintf "simulated://%s/%s/entries/%s" t.system org.id (Remote_id.to_string id))
;;

let connector t =
  Connector.T
    ( (module struct
        type nonrec t = t

        let system = system
        let authorization_url = authorization_url
        let complete_authorization = complete_authorization
        let disconnect = disconnect
        let chart = chart
        let tracking_categories = tracking_categories
        let period_lock = period_lock
        let post = post
        let poll = poll
        let void = void
        let view_url = view_url
      end)
    , t )
;;
