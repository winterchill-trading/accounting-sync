(** Export of double-entry ledger journals to external accounting systems.

    {!Export} turns ledger records into system-neutral {!Journal_entry}s through a
    {!Mapping} onto a {!Chart} of accounts, one entry per transaction and currency under
    an idempotent {!Entry_key}. A {!Tracker} holds each entry's {!Status}; {!Sync}
    pushes pending entries in {!Batch}es through a {!Connector} (such as {!Simulated})
    and polls for decisions; {!Reconciliation} checks a period against the ledger. *)

(** {1 Identifiers} *)

module Text_id = Text_id
module Account_code = Account_code
module Entry_key = Entry_key
module Push_key = Push_key
module Remote_id = Remote_id

(** {1 The external side} *)

module Chart = Chart
module Tracking = Tracking
module Organisation = Organisation
module Period = Period
module Period_lock = Period_lock

(** {1 Building entries} *)

module Journal_entry = Journal_entry
module Mapping = Mapping
module Export = Export
module Check = Check
module Batch = Batch

(** {1 Status and syncing} *)

module Reason = Reason
module Status = Status
module Tracker = Tracker
module Connection = Connection
module Connector = Connector
module Simulated = Simulated
module Sync = Sync
module Reconciliation = Reconciliation
