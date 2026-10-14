(** The checks an accounting system runs on a manual journal, in the order systems tend
    to run them, as a pure function. A sync runs them before sending so that an entry
    certain to be refused never leaves; {!Simulated} runs them to decide. *)

open! Core

(** The first problem found, or [None]: a line whose account is missing from [chart] or
    archived ([Unmapped_account], detail ["line N (code)"]), debits that differ from
    credits ([Unbalanced]), a tracking option [categories] do not have
    ([Unknown_tracking]), a date inside [lock] ([Period_locked]). *)
val entry
  :  chart:Chart.t
  -> categories:Tracking.Category.t list
  -> lock:Period_lock.t
  -> Journal_entry.t
  -> Reason.t option
