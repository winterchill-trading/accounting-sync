open! Async_kernel
open! Core

module Answer = struct
  type t =
    | Accepted of Remote_id.t
    | Posted of
        { remote : Remote_id.t
        ; number : string
        }
    | Rejected of
        { remote : Remote_id.t option
        ; reason : Reason.t
        }
  [@@deriving sexp, compare, equal]

  let to_event t ~at : Status.Event.t =
    match t with
    | Accepted remote -> Accepted { remote; at }
    | Posted { remote; number } -> Posted { remote; number; at }
    | Rejected { remote; reason } -> Rejected { remote; reason; at }
  ;;
end

module type S = sig
  type t

  val system : t -> string

  val authorization_url
    :  t
    -> state:string
    -> organisation_name:string
    -> string Deferred.Or_error.t

  val complete_authorization
    :  t
    -> state:string
    -> Organisation.t list Deferred.Or_error.t

  val disconnect : t -> Organisation.t -> unit Deferred.Or_error.t
  val chart : t -> Organisation.t -> Chart.t Deferred.Or_error.t

  val tracking_categories
    :  t
    -> Organisation.t
    -> Tracking.Category.t list Deferred.Or_error.t

  val period_lock : t -> Organisation.t -> Period_lock.t Deferred.Or_error.t

  val post
    :  t
    -> Organisation.t
    -> (Push_key.t * Journal_entry.t) list
    -> (Push_key.t * Answer.t) list Deferred.Or_error.t

  val poll
    :  t
    -> Organisation.t
    -> Remote_id.t list
    -> (Remote_id.t * Answer.t) list Deferred.Or_error.t

  val void : t -> Organisation.t -> Remote_id.t -> unit Deferred.Or_error.t
  val view_url : t -> Organisation.t -> Remote_id.t -> string option
end

type t = T : (module S with type t = 'a) * 'a -> t

let system (T ((module C), c)) = C.system c

let authorization_url (T ((module C), c)) ~state ~organisation_name =
  C.authorization_url c ~state ~organisation_name
;;

let complete_authorization (T ((module C), c)) ~state = C.complete_authorization c ~state
let disconnect (T ((module C), c)) org = C.disconnect c org
let chart (T ((module C), c)) org = C.chart c org
let tracking_categories (T ((module C), c)) org = C.tracking_categories c org
let period_lock (T ((module C), c)) org = C.period_lock c org
let post (T ((module C), c)) org entries = C.post c org entries
let poll (T ((module C), c)) org ids = C.poll c org ids
let void (T ((module C), c)) org id = C.void c org id
let view_url (T ((module C), c)) org id = C.view_url c org id
