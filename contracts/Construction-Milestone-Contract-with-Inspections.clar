(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-inspector (err u101))
(define-constant err-invalid-milestone (err u102))
(define-constant err-already-approved (err u103))
(define-constant err-not-approved (err u104))
(define-constant err-insufficient-funds (err u105))

(define-data-var total-milestones uint u0)
(define-data-var total-funds uint u0)

(define-map Milestones
    uint
    {
        description: (string-ascii 100),
        amount: uint,
        completed: bool,
        approved: bool,
        inspector: principal,
        deadline: uint,
    }
)

(define-map Inspectors
    principal
    bool
)

(define-map BuilderPayments
    uint
    {
        amount: uint,
        paid: bool,
        payment-date: uint,
    }
)

(define-public (add-milestone
        (description (string-ascii 100))
        (amount uint)
        (inspector principal)
        (deadline uint)
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> amount u0) err-invalid-milestone)
        (var-set total-milestones (+ (var-get total-milestones) u1))
        (var-set total-funds (+ (var-get total-funds) amount))
        (map-set Milestones (var-get total-milestones) {
            description: description,
            amount: amount,
            completed: false,
            approved: false,
            inspector: inspector,
            deadline: deadline,
        })
        (ok (var-get total-milestones))
    )
)

(define-public (register-inspector (inspector principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set Inspectors inspector true)
        (ok true)
    )
)

(define-public (mark-milestone-completed (milestone-id uint))
    (let ((milestone (unwrap! (map-get? Milestones milestone-id) err-invalid-milestone)))
        (asserts! (not (get completed milestone)) err-already-approved)
        (map-set Milestones milestone-id (merge milestone { completed: true }))
        (ok true)
    )
)

(define-public (approve-milestone (milestone-id uint))
    (let ((milestone (unwrap! (map-get? Milestones milestone-id) err-invalid-milestone)))
        (asserts! (is-eq (get inspector milestone) tx-sender) err-not-inspector)
        (asserts! (get completed milestone) err-not-approved)
        (asserts! (not (get approved milestone)) err-already-approved)
        (map-set Milestones milestone-id (merge milestone { approved: true }))
        (ok true)
    )
)

(define-public (release-payment (milestone-id uint))
    (let ((milestone (unwrap! (map-get? Milestones milestone-id) err-invalid-milestone)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (get approved milestone) err-not-approved)
        (map-set BuilderPayments milestone-id {
            amount: (get amount milestone),
            paid: true,
            payment-date: burn-block-height,
        })
        (ok true)
    )
)

(define-read-only (get-milestone (milestone-id uint))
    (map-get? Milestones milestone-id)
)

(define-read-only (get-payment-status (milestone-id uint))
    (map-get? BuilderPayments milestone-id)
)

(define-read-only (is-inspector (address principal))
    (default-to false (map-get? Inspectors address))
)

(define-read-only (get-total-milestones)
    (var-get total-milestones)
)

(define-read-only (get-total-funds)
    (var-get total-funds)
)
