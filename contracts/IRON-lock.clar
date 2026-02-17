;; ============================================================
;; IRON-lock - Decentralized Escrow Marketplace
;; ============================================================

;; ============================================================
;; ERROR CONSTANTS
;; ============================================================

(define-constant ERR_NOT_BUYER           (err u100))
(define-constant ERR_NOT_SELLER          (err u101))
(define-constant ERR_NOT_ARBITER         (err u102))
(define-constant ERR_NOT_PARTICIPANT     (err u103))
(define-constant ERR_ESCROW_NOT_FOUND    (err u104))
(define-constant ERR_WRONG_STATE         (err u105))
(define-constant ERR_ALREADY_CONFIRMED   (err u106))
(define-constant ERR_TRANSFER_FAILED     (err u107))
(define-constant ERR_ZERO_AMOUNT         (err u108))
(define-constant ERR_INVALID_FEE         (err u109))
(define-constant ERR_DEADLINE_NOT_PASSED (err u110))
(define-constant ERR_SELF_TRADE          (err u111))

;; ============================================================
;; STATE CONSTANTS
;; ============================================================

(define-constant STATE_PENDING   u0)
(define-constant STATE_DISPUTED  u2)
(define-constant STATE_RELEASED  u3)
(define-constant STATE_REFUNDED  u4)

(define-constant MAX_ARBITER_FEE_BPS u1000) ;; 10%
(define-constant PLATFORM_FEE_BPS    u50)   ;; 0.5%

;; Replace before mainnet deploy
(define-constant PLATFORM_ADDR 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)

;; ============================================================
;; STORAGE
;; ============================================================

(define-data-var escrow-count uint u0)

(define-map escrows
  {id: uint}
  {
    buyer:            principal,
    seller:           principal,
    arbiter:          principal,
    amount:           uint,
    arbiter-fee-bps:  uint,
    deadline:         uint,
    state:            uint,
    buyer-confirmed:  bool,
    seller-confirmed: bool
  })

(define-map dispute-rulings
  {escrow-id: uint}
  {favour: principal})

;; ============================================================
;; PRIVATE HELPERS
;; ============================================================

(define-private (bps-of (amount uint) (bps uint))
  (/ (* amount bps) u10000))

(define-private (get-escrow-record (escrow-id uint))
  (map-get? escrows {id: escrow-id}))

;; ============================================================
;; PUBLIC FUNCTIONS
;; ============================================================

;; ------------------------------------------------------------
;; create-escrow
;; ------------------------------------------------------------

(define-public (create-escrow
  (seller          principal)
  (arbiter         principal)
  (amount          uint)
  (arbiter-fee-bps uint)
  (duration        uint)
  (start-block     uint))

  (begin
    (asserts! (not (is-eq tx-sender seller)) ERR_SELF_TRADE)
    (asserts! (> amount u0) ERR_ZERO_AMOUNT)
    (asserts! (<= arbiter-fee-bps MAX_ARBITER_FEE_BPS) ERR_INVALID_FEE)

    (let (
          (id (+ u1 (var-get escrow-count)))
          (deadline (+ start-block duration)))

      (asserts!
        (is-ok (stx-transfer? amount tx-sender tx-sender))
        ERR_TRANSFER_FAILED)

      (map-set escrows
        {id: id}
        {
          buyer:            tx-sender,
          seller:           seller,
          arbiter:          arbiter,
          amount:           amount,
          arbiter-fee-bps:  arbiter-fee-bps,
          deadline:         deadline,
          state:            STATE_PENDING,
          buyer-confirmed:  false,
          seller-confirmed: false
        })

      (var-set escrow-count id)
      (ok id))))

;; ------------------------------------------------------------
;; confirm-delivery
;; ------------------------------------------------------------
(define-public (confirm-delivery (escrow-id uint))

  (let (
        (escrow (unwrap! (get-escrow-record escrow-id) ERR_ESCROW_NOT_FOUND)))

    (asserts! (is-eq (get state escrow) STATE_PENDING) ERR_WRONG_STATE)

    (asserts!
      (or (is-eq tx-sender (get buyer escrow))
          (is-eq tx-sender (get seller escrow)))
      ERR_NOT_PARTICIPANT)

    (let (
          (new-buyer-conf
            (or (get buyer-confirmed escrow)
                (is-eq tx-sender (get buyer escrow))))
          (new-seller-conf
            (or (get seller-confirmed escrow)
                (is-eq tx-sender (get seller escrow)))))

      (if (and new-buyer-conf new-seller-conf)

          (let (
                (amount       (get amount escrow))
                (platform-fee (bps-of amount PLATFORM_FEE_BPS))
                (net          (- amount platform-fee)))

            (map-set escrows
              {id: escrow-id}
              (merge escrow {state: STATE_RELEASED}))

            (asserts!
              (is-ok (stx-transfer? platform-fee tx-sender PLATFORM_ADDR))
              ERR_TRANSFER_FAILED)

            (asserts!
              (is-ok (stx-transfer? net tx-sender (get seller escrow)))
              ERR_TRANSFER_FAILED)

            (ok true))

          (begin
            (map-set escrows
              {id: escrow-id}
              (merge escrow
                {buyer-confirmed:  new-buyer-conf,
                 seller-confirmed: new-seller-conf}))
            (ok false))))))

;; ------------------------------------------------------------
;; raise-dispute
;; ------------------------------------------------------------
(define-public (raise-dispute (escrow-id uint))

  (let (
        (escrow (unwrap! (get-escrow-record escrow-id) ERR_ESCROW_NOT_FOUND)))

    (asserts! (is-eq (get state escrow) STATE_PENDING) ERR_WRONG_STATE)

    (asserts!
      (or (is-eq tx-sender (get buyer escrow))
          (is-eq tx-sender (get seller escrow)))
      ERR_NOT_PARTICIPANT)

    (map-set escrows
      {id: escrow-id}
      (merge escrow {state: STATE_DISPUTED}))

    (ok escrow-id)))

;; ------------------------------------------------------------
;; resolve-dispute
;; ------------------------------------------------------------
(define-public (resolve-dispute (escrow-id uint) (favour principal))

  (let (
        (escrow (unwrap! (get-escrow-record escrow-id) ERR_ESCROW_NOT_FOUND)))

    (asserts! (is-eq (get state escrow) STATE_DISPUTED) ERR_WRONG_STATE)
    (asserts! (is-eq tx-sender (get arbiter escrow)) ERR_NOT_ARBITER)

    (asserts!
      (or (is-eq favour (get buyer escrow))
          (is-eq favour (get seller escrow)))
      ERR_NOT_PARTICIPANT)

    (let (
          (amount       (get amount escrow))
          (arbiter-fee  (bps-of amount (get arbiter-fee-bps escrow)))
          (platform-fee (bps-of amount PLATFORM_FEE_BPS))
          (net          (- amount (+ arbiter-fee platform-fee)))
          (new-state    (if (is-eq favour (get seller escrow))
                           STATE_RELEASED
                           STATE_REFUNDED)))

      (map-set escrows
        {id: escrow-id}
        (merge escrow {state: new-state}))

      (map-set dispute-rulings
        {escrow-id: escrow-id}
        {favour: favour})

      (asserts!
        (is-ok (stx-transfer? platform-fee tx-sender PLATFORM_ADDR))
        ERR_TRANSFER_FAILED)

      (asserts!
        (is-ok (stx-transfer? arbiter-fee tx-sender (get arbiter escrow)))
        ERR_TRANSFER_FAILED)

      (asserts!
        (is-ok (stx-transfer? net tx-sender favour))
        ERR_TRANSFER_FAILED)

      (ok net))))
      
;; ------------------------------------------------------------
;; auto-refund
;; ------------------------------------------------------------

(define-public (auto-refund (escrow-id uint) (current-block uint))

  (let (
        (escrow (unwrap! (get-escrow-record escrow-id) ERR_ESCROW_NOT_FOUND)))

    (asserts! (is-eq (get state escrow) STATE_PENDING) ERR_WRONG_STATE)
    (asserts! (is-eq tx-sender (get buyer escrow)) ERR_NOT_BUYER)
    (asserts! (>= current-block (get deadline escrow)) ERR_DEADLINE_NOT_PASSED)

    (let (
          (amount       (get amount escrow))
          (platform-fee (bps-of amount PLATFORM_FEE_BPS))
          (net          (- amount platform-fee)))

      (map-set escrows
        {id: escrow-id}
        (merge escrow {state: STATE_REFUNDED}))

      (asserts!
        (is-ok (stx-transfer? platform-fee tx-sender PLATFORM_ADDR))
        ERR_TRANSFER_FAILED)

      (asserts!
        (is-ok (stx-transfer? net tx-sender (get buyer escrow)))
        ERR_TRANSFER_FAILED)

      (ok net))))
