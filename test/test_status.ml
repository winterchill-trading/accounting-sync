open! Core
open Accounting_sync

let at = Time_ns.epoch
let r1 = Remote_id.of_string "je_1"
let r2 = Remote_id.of_string "je_2"
let locked = Reason.create Period_locked

let states : (string * Status.t) list =
  [ "pending", Pending
  ; "submitted", Submitted { remote = r1; at }
  ; "posted", Posted { remote = r1; number = "JE-1"; at }
  ; "rejected", Rejected { reason = locked; remote = None; at }
  ; "voided", Voided { remote = Some r1; note = ""; at }
  ]
;;

let events : (string * Status.Event.t) list =
  [ "accepted", Accepted { remote = r1; at }
  ; "posted", Posted { remote = r1; number = "JE-1"; at }
  ; "posted(other)", Posted { remote = r2; number = "JE-2"; at }
  ; "rejected", Rejected { reason = locked; remote = None; at }
  ; "voided", Voided { note = "reversed"; at }
  ; "retry", Retry
  ]
;;

let%expect_test "transition table" =
  printf "%-10s" "";
  List.iter events ~f:(fun (e, _) -> printf "%-14s" e);
  print_endline "";
  List.iter states ~f:(fun (name, s) ->
    printf "%-10s" name;
    List.iter events ~f:(fun (_, e) ->
      printf
        "%-14s"
        (match Status.apply s e with
         | Ok s' -> Status.name s'
         | Error _ -> "-"));
    print_endline "");
  [%expect {|
              accepted      posted        posted(other) rejected      voided        retry
    pending   submitted     posted        posted        rejected      voided        -
    submitted submitted     posted        -             rejected      voided        -
    posted    -             posted        -             -             voided        -
    rejected  -             -             -             rejected      voided        pending
    voided    -             -             -             -             voided        pending
    |}]
;;

let%test_unit "posted entries only leave by a void, and remote ids never change" =
  let event_gen = Quickcheck.Generator.of_list (List.map events ~f:snd) in
  Quickcheck.test
    (List.gen_with_length 12 event_gen)
    ~sexp_of:[%sexp_of: Status.Event.t list]
    ~f:(fun evs ->
      ignore
        (List.fold evs ~init:Status.Pending ~f:(fun s e ->
           match Status.apply s e with
           | Error _ -> s
           | Ok s' ->
             (match s, s' with
              | Posted _, (Posted _ | Voided _) -> ()
              | Posted _, _ -> failwith "posted entry left without a void"
              | _ -> ());
             (match Status.remote s, Status.remote s' with
              | Some a, Some b when not (Remote_id.equal a b) ->
                failwith "remote id changed within an attempt"
              | _ -> ());
             s')
         : Status.t))
;;
