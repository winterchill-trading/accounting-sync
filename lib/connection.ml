open! Core

module Stable = struct
  module V1 = struct
    type t =
      | Pending of
          { state : string
          ; started_at : Time_ns.Stable.Alternate_sexp.V1.t
          }
      | Connected of
          { organisation : Organisation.Stable.V1.t
          ; connected_at : Time_ns.Stable.Alternate_sexp.V1.t
          }
      | Disconnected of
          { organisation : Organisation.Stable.V1.t
          ; at : Time_ns.Stable.Alternate_sexp.V1.t
          }
      | Cancelled of { at : Time_ns.Stable.Alternate_sexp.V1.t }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1

let name = function
  | Pending _ -> "pending"
  | Connected _ -> "connected"
  | Disconnected _ -> "disconnected"
  | Cancelled _ -> "cancelled"
;;

let not_allowed t what =
  Or_error.error_s [%message "connection transition not allowed" what ~from:(name t)]
;;

let start ~state ~at =
  if String.is_empty state
  then Or_error.error_string "consent state must not be empty"
  else Ok (Pending { state; started_at = at })
;;

let select t ~state ~granted ~organisation ~at =
  match t with
  | Pending p when not (String.equal p.state state) ->
    Or_error.error_string "consent state does not match this connection"
  | Pending _ when not (List.mem granted organisation ~equal:Organisation.equal) ->
    Or_error.error_s
      [%message "organisation not covered by the consent" (organisation : Organisation.t)]
  | Pending _ -> Ok (Connected { organisation; connected_at = at })
  | _ -> not_allowed t "select"
;;

let cancel t ~at =
  match t with
  | Pending _ -> Ok (Cancelled { at })
  | _ -> not_allowed t "cancel"
;;

let disconnect t ~at =
  match t with
  | Connected { organisation; _ } -> Ok (Disconnected { organisation; at })
  | _ -> not_allowed t "disconnect"
;;

let connected = function
  | Connected { organisation; _ } -> Some organisation
  | _ -> None
;;
