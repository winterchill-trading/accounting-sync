open! Core

module T = struct
  type t =
    { year : int
    ; month : Month.Stable.V1.t
    }
  [@@deriving bin_io, compare, equal, hash]

  let to_string t = sprintf "%04d-%02d" t.year (Month.to_int t.month)

  let of_string_or_error s =
    Or_error.try_with (fun () ->
      match String.split s ~on:'-' with
      | [ y; m ] when String.length y = 4 && String.length m = 2 ->
        { year = Int.of_string y; month = Month.of_int_exn (Int.of_string m) }
      | _ -> failwith "expected YYYY-MM")
    |> Or_error.tag_s ~tag:[%message "invalid period" s]
  ;;

  let sexp_of_t t = Sexp.Atom (to_string t)
  let t_of_sexp sexp = Or_error.ok_exn (of_string_or_error (string_of_sexp sexp))
end

include T
include Comparable.Make (T)

let create ~year ~month = { year; month }
let of_date d = { year = Date.year d; month = Date.month d }
let first_day t = Date.create_exn ~y:t.year ~m:t.month ~d:1

let last_day t =
  Date.create_exn ~y:t.year ~m:t.month ~d:(Date.days_in_month ~year:t.year ~month:t.month)
;;

let contains t d = equal t (of_date d)
let next t = of_date (Date.add_days (last_day t) 1)
let prev t = of_date (Date.add_days (first_day t) (-1))

module Stable = struct
  module V1 = T
end
