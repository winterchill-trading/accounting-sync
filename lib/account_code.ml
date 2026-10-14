open! Core

include
  Text_id.Make
    (struct
      let module_name = "Accounting_sync.Account_code"
      let max_length = 64
    end)
    ()
