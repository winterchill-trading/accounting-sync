open! Core

include
  Text_id.Make
    (struct
      let module_name = "Accounting_sync.Push_key"
      let max_length = Entry_key.max_length + 12
    end)
    ()

let create entry ~attempt =
  if Int.( < ) attempt 1
  then Or_error.error_s [%message "attempt must be at least 1" (attempt : int)]
  else of_string_or_error (sprintf "%s:%d" (Entry_key.to_string entry) attempt)
;;

let create_exn entry ~attempt = Or_error.ok_exn (create entry ~attempt)
