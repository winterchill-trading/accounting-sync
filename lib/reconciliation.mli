(** Checks what the remote system holds for a period against the ledger.

    Three views of the same period, per currency and external account:
    - [ledger]: the net movement of every ledger posting in the period, placed by the
      mapping (postings it cannot place appear under no account);
    - [exported]: the net movement of the entries an export builds now;
    - [posted]: the net movement of the entries the tracker says are posted.

    [ledger] and [exported] differ only where entries are blocked; [exported] and
    [posted] differ where something is not pushed, pending, rejected, changed after
    posting, or posted but no longer in the export ("extra"). A period reconciles when
    all three agree and every entry is posted unchanged. *)

open! Core

module Account_line : sig
  type t =
    { currency : Money.Currency.t
    ; account : Account_code.t option (** [None]: postings the mapping cannot place *)
    ; ledger : Money.Amount.t (** net, debits positive *)
    ; exported : Money.Amount.t
    ; posted : Money.Amount.t
    }
  [@@deriving sexp_of, compare, equal]

  val matched : t -> bool
end

module Currency_line : sig
  type t =
    { currency : Money.Currency.t
    ; exported_debits : Money.Amount.t
    ; posted_debits : Money.Amount.t
    ; exported_lines : int
    ; posted_lines : int
    }
  [@@deriving sexp_of, compare, equal]

  val matched : t -> bool
end

type t =
  { from : Date.t
  ; to_ : Date.t
  ; entries : int (** entries the export builds for the period *)
  ; matched : int (** posted with the same content *)
  ; not_pushed : int (** never sent, or voided *)
  ; pending : int (** sent or about to be, no decision yet *)
  ; rejected : int
  ; changed : int (** posted, but the export now builds different content *)
  ; extra : int (** posted, dated in the period, but no longer exported *)
  ; blocked : int (** transactions the mapping cannot place *)
  ; currencies : Currency_line.t list
  ; accounts : Account_line.t list (** only lines where the three views differ, unless [~all] *)
  }
[@@deriving sexp_of]

(** Whether everything is posted unchanged and every total agrees. *)
val reconciled : t -> bool

val run
  :  ?basis:Export.Date_basis.t
  -> ?touching:(Ledger.Account_id.t -> bool)
  -> ?all:bool (** keep matching account lines too; default [false] *)
  -> mapping:Mapping.t
  -> from:Date.t
  -> to_:Date.t
  -> Ledger.Record.t list
  -> Tracker.t
  -> t
