open! Core

include
  Text_id.Make
    (struct
      let module_name = "Accounting_sync.Remote_id"
      let max_length = 128
    end)
    ()
