open! Core

module Line = struct
  module Stable = struct
    module V1 = struct
      type t =
        { account : Account_code.Stable.V1.t
        ; side : Ledger.Side.Stable.V1.t
        ; amount : Money.Amount.Stable.V1.t
        ; description : string
        ; tracking : Tracking.Assignment.Stable.V1.t list
        ; sources : Ledger.Account_id.Stable.V1.t list
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1

  let signed t =
    match t.side with
    | Debit -> t.amount
    | Credit -> Money.Amount.neg t.amount
  ;;
end

module Repr = struct
  type t =
    { key : Entry_key.Stable.V1.t
    ; transaction : Ledger.Idempotency_key.Stable.V1.t
    ; date : Date.Stable.V1.t
    ; currency : Money.Currency.Stable.V1.t
    ; fx : Money.Rate.Stable.V1.t option
    ; narration : string
    ; reference : string
    ; lines : Line.Stable.V1.t list
    }
  [@@deriving bin_io, sexp, compare, equal]
end

include Repr

let max_narration = 500

let validate (t : t) =
  let open Or_error.Let_syntax in
  let fail msg = Or_error.error_s [%message msg ~key:(t.key : Entry_key.t)] in
  let%bind () =
    match t.fx with
    | Some rate when not (Money.Currency.equal (Money.Rate.base rate) t.currency) ->
      fail "exchange rate base is not the entry currency"
    | _ -> Ok ()
  in
  let%bind () =
    match t.lines with
    | [] | [ _ ] -> fail "an entry needs at least two lines"
    | _ -> Ok ()
  in
  let%bind () =
    match
      List.find t.lines ~f:(fun (l : Line.t) ->
        (not (Money.Currency.equal (Money.Amount.currency l.amount) t.currency))
        || not (Money.Amount.is_positive l.amount))
    with
    | Some _ -> fail "every line needs a positive amount in the entry currency"
    | None -> Ok ()
  in
  let net =
    List.fold t.lines ~init:(Money.Amount.zero t.currency) ~f:(fun acc l ->
      Money.Amount.add_exn acc (Line.signed l))
  in
  if Money.Amount.is_zero net
  then Ok ()
  else
    Or_error.error_s
      [%message
        "unbalanced entry"
          ~key:(t.key : Entry_key.t)
          ~debits_minus_credits:(Money.Amount.to_string net)]
;;

let create ~key ~transaction ~date ~currency ?fx ?(narration = "") ?(reference = "") lines
  =
  let narration =
    if String.length narration > max_narration
    then String.prefix narration max_narration
    else narration
  in
  let t = { key; transaction; date; currency; fx; narration; reference; lines } in
  Or_error.map (validate t) ~f:(fun () -> t)
;;

let total t =
  List.fold t.lines ~init:(Money.Amount.zero t.currency) ~f:(fun acc (l : Line.t) ->
    match l.side with
    | Debit -> Money.Amount.add_exn acc l.amount
    | Credit -> acc)
;;

(* The stable sexp is the canonical form: it names every field and its text never changes
   with the unstable type's derivations. *)
let digest t = Md5.to_hex (Md5.digest_string (Sexp.to_string (Repr.sexp_of_t t)))

module Stable = struct
  module V1 = struct
    include Repr

    let of_repr t = Or_error.ok_exn (Or_error.map (validate t) ~f:(fun () -> t))
    let t_of_sexp sexp = of_repr (Repr.t_of_sexp sexp)

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Repr)
        (struct
          type t = Repr.t

          let to_binable = Fn.id
          let of_binable = of_repr
        end)
  end
end
