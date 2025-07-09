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
(define-constant err-dispute-exists (err u106))
(define-constant err-no-dispute (err u107))
(define-constant err-not-arbitrator (err u108))
(define-constant err-dispute-resolved (err u109))

(define-data-var arbitrator principal tx-sender)

(define-map Disputes
    uint
    {
        milestone-id: uint,
        raised-by: principal,
        reason: (string-ascii 200),
        status: (string-ascii 20),
        resolution: (string-ascii 200),
        created-at: uint,
        resolved-at: uint,
    }
)

(define-data-var dispute-counter uint u0)

(define-public (set-arbitrator (new-arbitrator principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set arbitrator new-arbitrator)
        (ok true)
    )
)

(define-public (raise-dispute
        (milestone-id uint)
        (reason (string-ascii 200))
    )
    (let (
            (milestone (unwrap! (map-get? Milestones milestone-id) err-invalid-milestone))
            (dispute-id (+ (var-get dispute-counter) u1))
        )
        (asserts!
            (or
                (is-eq tx-sender (get inspector milestone))
                (is-eq tx-sender contract-owner)
            )
            err-not-inspector
        )
        ;; For simplicity, we'll allow multiple disputes per milestone and track them
        ;; This removes the circular dependency issue
        (var-set dispute-counter dispute-id)
        (map-set Disputes dispute-id {
            milestone-id: milestone-id,
            raised-by: tx-sender,
            reason: reason,
            status: "open",
            resolution: "",
            created-at: burn-block-height,
            resolved-at: u0,
        })
        (ok dispute-id)
    )
)

(define-public (resolve-dispute
        (dispute-id uint)
        (resolution (string-ascii 200))
        (should-approve bool)
    )
    (let (
            (dispute (unwrap! (map-get? Disputes dispute-id) err-no-dispute))
            (milestone-id (get milestone-id dispute))
            (milestone (unwrap! (map-get? Milestones milestone-id) err-invalid-milestone))
        )
        (asserts! (is-eq tx-sender (var-get arbitrator)) err-not-arbitrator)
        (asserts! (is-eq (get status dispute) "open") err-dispute-resolved)
        (map-set Disputes dispute-id
            (merge dispute {
                status: "resolved",
                resolution: resolution,
                resolved-at: burn-block-height,
            })
        )
        (if should-approve
            (map-set Milestones milestone-id (merge milestone { approved: true }))
            true
        )
        (ok true)
    )
)

(define-read-only (get-dispute (dispute-id uint))
    (map-get? Disputes dispute-id)
)

(define-read-only (get-arbitrator)
    (var-get arbitrator)
)
(define-constant err-milestone-overdue (err u110))
(define-constant err-invalid-penalty-rate (err u111))

(define-data-var penalty-rate uint u5)
(define-data-var grace-period uint u144)

(define-map MilestonePenalties
    uint
    {
        penalty-amount: uint,
        days-overdue: uint,
        calculated-at: uint,
    }
)

(define-public (set-penalty-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-rate u50) err-invalid-penalty-rate)
        (var-set penalty-rate new-rate)
        (ok true)
    )
)

(define-public (set-grace-period (blocks uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set grace-period blocks)
        (ok true)
    )
)

(define-public (calculate-penalty (milestone-id uint))
    (let (
            (milestone (unwrap! (map-get? Milestones milestone-id) err-invalid-milestone))
            (current-block burn-block-height)
            (deadline (get deadline milestone))
            (grace-end (+ deadline (var-get grace-period)))
        )
        (if (> current-block grace-end)
            (let (
                    (days-overdue (/ (- current-block grace-end) u144))
                    (base-amount (get amount milestone))
                    (penalty-amount (/ (* base-amount (var-get penalty-rate) days-overdue) u100))
                )
                (map-set MilestonePenalties milestone-id {
                    penalty-amount: penalty-amount,
                    days-overdue: days-overdue,
                    calculated-at: current-block,
                })
                (ok penalty-amount)
            )
            (ok u0)
        )
    )
)

(define-public (extend-deadline
        (milestone-id uint)
        (new-deadline uint)
    )
    (let ((milestone (unwrap! (map-get? Milestones milestone-id) err-invalid-milestone)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (not (get completed milestone)) err-already-approved)
        (asserts! (> new-deadline burn-block-height) err-invalid-milestone)
        (map-set Milestones milestone-id
            (merge milestone { deadline: new-deadline })
        )
        (ok true)
    )
)

(define-public (release-payment-with-penalty (milestone-id uint))
    (let (
            (milestone (unwrap! (map-get? Milestones milestone-id) err-invalid-milestone))
            (penalty-info (calculate-penalty milestone-id))
            (penalty-amount (unwrap-panic penalty-info))
            (final-amount (- (get amount milestone) penalty-amount))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (get approved milestone) err-not-approved)
        (map-set BuilderPayments milestone-id {
            amount: final-amount,
            paid: true,
            payment-date: burn-block-height,
        })
        (ok final-amount)
    )
)

(define-read-only (get-milestone-penalty (milestone-id uint))
    (map-get? MilestonePenalties milestone-id)
)

(define-read-only (is-milestone-overdue (milestone-id uint))
    (let ((milestone (map-get? Milestones milestone-id)))
        (if (is-some milestone)
            (let (
                    (deadline (get deadline (unwrap-panic milestone)))
                    (grace-end (+ deadline (var-get grace-period)))
                )
                (> burn-block-height grace-end)
            )
            false
        )
    )
)

(define-read-only (get-penalty-settings)
    {
        penalty-rate: (var-get penalty-rate),
        grace-period: (var-get grace-period),
    }
)

(define-read-only (get-milestone-status (milestone-id uint))
    (let ((milestone (map-get? Milestones milestone-id)))
        (if (is-some milestone)
            (let (
                    (m (unwrap-panic milestone))
                    (current-block burn-block-height)
                    (deadline (get deadline m))
                    (grace-end (+ deadline (var-get grace-period)))
                )
                (some {
                    milestone: m,
                    is-overdue: (> current-block grace-end),
                    blocks-until-deadline: (if (> deadline current-block)
                        (- deadline current-block)
                        u0
                    ),
                    blocks-overdue: (if (> current-block grace-end)
                        (- current-block grace-end)
                        u0
                    ),
                })
            )
            none
        )
    )
)
