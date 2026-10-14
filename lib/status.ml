open! Core

module Stable = struct
  module V1 = struct
    type t =
      | Pending
      | Submitted of
          { remote : Remote_id.Stable.V1.t
          ; at : Time_ns.Stable.Alternate_sexp.V1.t
          }
      | Posted of
          { remote : Remote_id.Stable.V1.t
          ; number : string
          ; at : Time_ns.Stable.Alternate_sexp.V1.t
          }
      | Rejected of
          { reason : Reason.Stable.V1.t
          ; remote : Remote_id.Stable.V1.t option
          ; at : Time_ns.Stable.Alternate_sexp.V1.t
          }
      | Voided of
          { remote : Remote_id.Stable.V1.t option
          ; note : string
          ; at : Time_ns.Stable.Alternate_sexp.V1.t
          }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1

module Event = struct
  type t =
    | Accepted of
        { remote : Remote_id.t
        ; at : Time_ns.Alternate_sexp.t
        }
    | Posted of
        { remote : Remote_id.t
        ; number : string
        ; at : Time_ns.Alternate_sexp.t
        }
    | Rejected of
        { reason : Reason.t
        ; remote : Remote_id.t option
        ; at : Time_ns.Alternate_sexp.t
        }
    | Voided of
        { note : string
        ; at : Time_ns.Alternate_sexp.t
        }
    | Retry
  [@@deriving sexp, compare, equal]
end

let name = function
  | Pending -> "pending"
  | Submitted _ -> "submitted"
  | Posted _ -> "posted"
  | Rejected _ -> "rejected"
  | Voided _ -> "voided"
;;

let remote = function
  | Pending -> None
  | Submitted { remote; _ } | Posted { remote; _ } -> Some remote
  | Rejected { remote; _ } | Voided { remote; _ } -> remote
;;

let is_open = function
  | Pending | Submitted _ -> true
  | Posted _ | Rejected _ | Voided _ -> false
;;

let remote_of_open = function
  | Submitted { remote; _ } -> Some remote
  | _ -> None
;;

let same_remote expected got =
  match expected with
  | None -> true
  | Some r -> Remote_id.equal r got
;;

let apply t (event : Event.t) =
  let refuse () =
    Or_error.error_s
      [%message "status transition not allowed" ~from:(t : t) (event : Event.t)]
  in
  match t, event with
  | Pending, Accepted { remote; at } -> Ok (Submitted { remote; at })
  | (Pending | Submitted _), Posted { remote; number; at }
    when same_remote (remote_of_open t) remote -> Ok (Posted { remote; number; at })
  | (Pending | Submitted _), Rejected { reason; remote; at }
    when Option.for_all remote ~f:(same_remote (remote_of_open t)) ->
    let remote = Option.first_some remote (remote_of_open t) in
    Ok (Rejected { reason; remote; at })
  (* Overlapping polls repeat answers; a repeat of the recorded one is not an error. *)
  | Submitted { remote = r; _ }, Accepted { remote; _ } when Remote_id.equal r remote ->
    Ok t
  | Posted { remote = r; _ }, Posted { remote; _ } when Remote_id.equal r remote -> Ok t
  | Rejected _, Rejected _ -> Ok t
  | (Pending | Submitted _ | Posted _ | Rejected _), Voided { note; at } ->
    Ok (Voided { remote = remote t; note; at })
  | Voided _, Voided _ -> Ok t
  | (Rejected _ | Voided _), Retry -> Ok Pending
  | _ -> refuse ()
;;
