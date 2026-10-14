open! Core
open Accounting_sync
open Helpers

let account ?(tags = []) s kind = Ledger.Account.create ~tags (id s) kind

let%expect_test "rules from most to least specific" =
  let m =
    Mapping.create_exn
      [ Class Liability, code "2999"
      ; Prefix "customer:", code "2000"
      ; Prefix "customer:vip", code "2010"
      ; Account (id "customer:vip-7"), code "2011"
      ; Tag { key = "product"; value = "savings" }, code "2050"
      ]
  in
  let show s ?tags kind =
    let a = account s ?tags kind in
    printf
      "%-22s %s\n"
      s
      (Option.value_map
         (Mapping.resolve m (Ledger.Account.id a) ~account:(Some a))
         ~default:"unmapped"
         ~f:Account_code.to_string)
  in
  show "customer:vip-7" Liability;
  show "customer:vip-8" Liability;
  show "customer:1" Liability;
  show "pots:3" Liability ~tags:[ "product", "savings" ];
  show "pots:4" Liability;
  show "bank:x" Asset;
  (* A pending sub-account maps like its parent. *)
  printf
    "%s\n"
    (Mapping.resolve m (Ledger.Account_id.pending (id "customer:vip-7")) ~account:None
     |> Option.value_map ~default:"unmapped" ~f:Account_code.to_string);
  [%expect {|
    customer:vip-7         2011
    customer:vip-8         2010
    customer:1             2000
    pots:3                 2050
    pots:4                 2999
    bank:x                 unmapped
    2011
    |}]
;;

let%expect_test "checking a mapping against a chart" =
  let m =
    Mapping.set mapping (Prefix "suspense:") (code "9999")
    |> fun m -> Mapping.set m (Prefix "legacy:") (code "7777")
  in
  print_s
    [%sexp
      (Mapping.check m ~chart ~categories : Mapping.Problem.t list)];
  let m = Mapping.create_exn ~tracking:[ "region", "Region" ] [] in
  print_s [%sexp (Mapping.check m ~chart ~categories : Mapping.Problem.t list)];
  print_s [%sexp (Mapping.check mapping ~chart ~categories : Mapping.Problem.t list)];
  [%expect {|
    ((Archived_code (rule (Prefix suspense:)) (code 9999))
     (Unknown_code (rule (Prefix legacy:)) (code 7777)))
    ((Unknown_category (category Region)))
    ()
    |}]
;;

let%expect_test "duplicate rules are refused; set replaces" =
  print_s
    [%sexp
      (Mapping.create [ Prefix "a", code "1"; Prefix "a", code "2" ] : Mapping.t Or_error.t)];
  let m = Mapping.set (Mapping.create_exn [ Prefix "a", code "1" ]) (Prefix "a") (code "2") in
  print_s [%sexp (Mapping.rules m : (Mapping.Rule.t * Account_code.t) list)];
  print_s [%sexp (Mapping.rules (Mapping.remove m (Prefix "a")) : (Mapping.Rule.t * Account_code.t) list)];
  [%expect {|
    (Error ("rule mapped twice" (rule (Prefix a))))
    (((Prefix a) 2))
    ()
    |}]
;;

let%expect_test "tracking from account tags" =
  let a = account "customer:1" Liability ~tags:[ "segment", "retail" ] in
  print_s [%sexp (Mapping.tracking mapping ~account:(Some a) : Tracking.Assignment.t list)];
  print_s [%sexp (Mapping.tracking mapping ~account:None : Tracking.Assignment.t list)];
  print_s
    [%sexp
      (Tracking.check categories [ { category = "Cost centre"; option = "ops" } ]
       : unit Or_error.t)];
  [%expect {|
    (((category "Cost centre") (option retail)))
    ()
    (Error ("unknown tracking option" (category "Cost centre") (option ops)))
    |}]
;;
