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

(define-constant err-invalid-progress (err u112))
(define-constant err-progress-exists (err u113))

(define-data-var progress-counter uint u0)

(define-map MilestoneProgress
    uint
    {
        milestone-id: uint,
        progress-percentage: uint,
        description: (string-ascii 150),
        evidence-link: (string-ascii 200),
        updated-by: principal,
        timestamp: uint,
        previous-progress-id: uint,
    }
)

(define-map MilestoneLatestProgress
    uint
    uint
)

(define-public (update-milestone-progress
        (milestone-id uint)
        (progress-percentage uint)
        (description (string-ascii 150))
        (evidence-link (string-ascii 200))
    )
    (let (
            (milestone (unwrap! (map-get? Milestones milestone-id) err-invalid-milestone))
            (progress-id (+ (var-get progress-counter) u1))
            (current-latest (default-to u0 (map-get? MilestoneLatestProgress milestone-id)))
        )
        (asserts! (<= progress-percentage u100) err-invalid-progress)
        (asserts! (not (get completed milestone)) err-already-approved)
        (var-set progress-counter progress-id)
        (map-set MilestoneProgress progress-id {
            milestone-id: milestone-id,
            progress-percentage: progress-percentage,
            description: description,
            evidence-link: evidence-link,
            updated-by: tx-sender,
            timestamp: burn-block-height,
            previous-progress-id: current-latest,
        })
        (map-set MilestoneLatestProgress milestone-id progress-id)
        (ok progress-id)
    )
)

(define-read-only (get-milestone-progress (progress-id uint))
    (map-get? MilestoneProgress progress-id)
)

(define-read-only (get-latest-progress (milestone-id uint))
    (let ((latest-id (map-get? MilestoneLatestProgress milestone-id)))
        (if (is-some latest-id)
            (map-get? MilestoneProgress (unwrap-panic latest-id))
            none
        )
    )
)

(define-read-only (get-milestone-progress-summary (milestone-id uint))
    (let (
            (milestone (map-get? Milestones milestone-id))
            (latest-progress (get-latest-progress milestone-id))
        )
        (if (and (is-some milestone) (is-some latest-progress))
            (some {
                milestone-info: (unwrap-panic milestone),
                current-progress: (get progress-percentage (unwrap-panic latest-progress)),
                last-update: (get timestamp (unwrap-panic latest-progress)),
                updated-by: (get updated-by (unwrap-panic latest-progress)),
            })
            none
        )
    )
)

(define-constant err-invalid-budget (err u114))
(define-constant err-budget-exceeded (err u115))
(define-constant err-no-budget-allocation (err u116))

(define-map MilestoneBudget
    uint
    {
        materials-budget: uint,
        labor-budget: uint,
        equipment-budget: uint,
        total-allocated: uint,
        created-at: uint,
    }
)

(define-map MilestoneExpenses
    uint
    {
        materials-actual: uint,
        labor-actual: uint,
        equipment-actual: uint,
        total-spent: uint,
        last-updated: uint,
    }
)

(define-public (set-milestone-budget
        (milestone-id uint)
        (materials-budget uint)
        (labor-budget uint)
        (equipment-budget uint)
    )
    (let (
            (milestone (unwrap! (map-get? Milestones milestone-id) err-invalid-milestone))
            (total-budget (+ (+ materials-budget labor-budget) equipment-budget))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-eq total-budget (get amount milestone)) err-invalid-budget)
        (asserts! (> materials-budget u0) err-invalid-budget)
        (asserts! (> labor-budget u0) err-invalid-budget)
        (asserts! (> equipment-budget u0) err-invalid-budget)
        (map-set MilestoneBudget milestone-id {
            materials-budget: materials-budget,
            labor-budget: labor-budget,
            equipment-budget: equipment-budget,
            total-allocated: total-budget,
            created-at: burn-block-height,
        })
        (map-set MilestoneExpenses milestone-id {
            materials-actual: u0,
            labor-actual: u0,
            equipment-actual: u0,
            total-spent: u0,
            last-updated: burn-block-height,
        })
        (ok true)
    )
)

(define-public (record-expense
        (milestone-id uint)
        (expense-category (string-ascii 20))
        (amount uint)
    )
    (let (
            (milestone (unwrap! (map-get? Milestones milestone-id) err-invalid-milestone))
            (budget (unwrap! (map-get? MilestoneBudget milestone-id)
                err-no-budget-allocation
            ))
            (current-expenses (unwrap! (map-get? MilestoneExpenses milestone-id)
                err-no-budget-allocation
            ))
        )
        (asserts! (not (get completed milestone)) err-already-approved)
        (asserts! (> amount u0) err-invalid-budget)
        (if (is-eq expense-category "materials")
            (let (
                    (new-materials (+ (get materials-actual current-expenses) amount))
                    (new-total (+ (get total-spent current-expenses) amount))
                )
                (asserts! (<= new-materials (get materials-budget budget))
                    err-budget-exceeded
                )
                (map-set MilestoneExpenses milestone-id
                    (merge current-expenses {
                        materials-actual: new-materials,
                        total-spent: new-total,
                        last-updated: burn-block-height,
                    })
                )
                (ok true)
            )
            (if (is-eq expense-category "labor")
                (let (
                        (new-labor (+ (get labor-actual current-expenses) amount))
                        (new-total (+ (get total-spent current-expenses) amount))
                    )
                    (asserts! (<= new-labor (get labor-budget budget))
                        err-budget-exceeded
                    )
                    (map-set MilestoneExpenses milestone-id
                        (merge current-expenses {
                            labor-actual: new-labor,
                            total-spent: new-total,
                            last-updated: burn-block-height,
                        })
                    )
                    (ok true)
                )
                (if (is-eq expense-category "equipment")
                    (let (
                            (new-equipment (+ (get equipment-actual current-expenses) amount))
                            (new-total (+ (get total-spent current-expenses) amount))
                        )
                        (asserts!
                            (<= new-equipment (get equipment-budget budget))
                            err-budget-exceeded
                        )
                        (map-set MilestoneExpenses milestone-id
                            (merge current-expenses {
                                equipment-actual: new-equipment,
                                total-spent: new-total,
                                last-updated: burn-block-height,
                            })
                        )
                        (ok true)
                    )
                    err-invalid-budget
                )
            )
        )
    )
)

(define-read-only (get-milestone-budget (milestone-id uint))
    (map-get? MilestoneBudget milestone-id)
)

(define-read-only (get-milestone-expenses (milestone-id uint))
    (map-get? MilestoneExpenses milestone-id)
)

(define-read-only (get-budget-analysis (milestone-id uint))
    (let (
            (budget (map-get? MilestoneBudget milestone-id))
            (expenses (map-get? MilestoneExpenses milestone-id))
        )
        (if (and (is-some budget) (is-some expenses))
            (let (
                    (b (unwrap-panic budget))
                    (e (unwrap-panic expenses))
                )
                (some {
                    materials-variance: (- (get materials-budget b) (get materials-actual e)),
                    labor-variance: (- (get labor-budget b) (get labor-actual e)),
                    equipment-variance: (- (get equipment-budget b) (get equipment-actual e)),
                    total-variance: (- (get total-allocated b) (get total-spent e)),
                    budget-utilization: (/ (* (get total-spent e) u100) (get total-allocated b)),
                })
            )
            none
        )
    )
)

;; ===== CONTRACTOR QUALITY RATING SYSTEM =====
;; Independent feature for tracking contractor performance ratings

(define-constant err-invalid-rating (err u117))
(define-constant err-already-rated (err u118))
(define-constant err-contractor-not-found (err u119))
(define-constant err-unauthorized-rater (err u120))
(define-constant err-contractor-blacklisted (err u121))
(define-constant err-invalid-threshold (err u122))

(define-data-var rating-counter uint u0)
(define-data-var blacklist-threshold uint u200) ;; 2.0 stars (out of 500 = 5.0 stars)

(define-map ContractorRatings
    uint
    {
        contractor: principal,
        rater: principal,
        rating: uint,
        milestone-id: uint,
        comment: (string-ascii 200),
        timestamp: uint,
    }
)

(define-map ContractorProfiles
    principal
    {
        total-ratings: uint,
        rating-sum: uint,
        average-rating: uint,
        is-blacklisted: bool,
        last-rating-update: uint,
    }
)

(define-map RatingHistory
    {
        contractor: principal,
        rater: principal,
        milestone-id: uint,
    }
    bool
)

(define-public (rate-contractor
        (contractor principal)
        (rating uint)
        (milestone-id uint)
        (comment (string-ascii 200))
    )
    (let (
            (milestone (unwrap! (map-get? Milestones milestone-id) err-invalid-milestone))
            (rating-id (+ (var-get rating-counter) u1))
            (rating-key {
                contractor: contractor,
                rater: tx-sender,
                milestone-id: milestone-id,
            })
            (current-profile (default-to {
                total-ratings: u0,
                rating-sum: u0,
                average-rating: u0,
                is-blacklisted: false,
                last-rating-update: u0,
            }
                (map-get? ContractorProfiles contractor)
            ))
        )
        ;; Validate inputs
        (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
        (asserts! (get approved milestone) err-not-approved)
        (asserts! (is-none (map-get? RatingHistory rating-key)) err-already-rated)

        ;; Only allow contract owner, inspector, or milestone participants to rate
        (asserts!
            (or
                (is-eq tx-sender contract-owner)
                (is-eq tx-sender (get inspector milestone))
                (is-inspector tx-sender)
            )
            err-unauthorized-rater
        )

        ;; Record the rating
        (var-set rating-counter rating-id)
        (map-set ContractorRatings rating-id {
            contractor: contractor,
            rater: tx-sender,
            rating: rating,
            milestone-id: milestone-id,
            comment: comment,
            timestamp: burn-block-height,
        })

        ;; Mark as rated to prevent duplicates
        (map-set RatingHistory rating-key true)

        ;; Update contractor profile
        (let (
                (new-total (+ (get total-ratings current-profile) u1))
                (new-sum (+ (get rating-sum current-profile) (* rating u100)))
                (new-average (/ new-sum new-total))
                (should-blacklist (< new-average (var-get blacklist-threshold)))
            )
            (map-set ContractorProfiles contractor {
                total-ratings: new-total,
                rating-sum: new-sum,
                average-rating: new-average,
                is-blacklisted: (and (>= new-total u3) should-blacklist),
                last-rating-update: burn-block-height,
            })
        )

        (ok rating-id)
    )
)

(define-public (update-rating-threshold (new-threshold uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (and (>= new-threshold u100) (<= new-threshold u500))
            err-invalid-threshold
        )
        (var-set blacklist-threshold new-threshold)
        (ok true)
    )
)

(define-public (manually-blacklist-contractor
        (contractor principal)
        (blacklist bool)
    )
    (let ((current-profile (default-to {
            total-ratings: u0,
            rating-sum: u0,
            average-rating: u0,
            is-blacklisted: false,
            last-rating-update: u0,
        }
            (map-get? ContractorProfiles contractor)
        )))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set ContractorProfiles contractor
            (merge current-profile { is-blacklisted: blacklist })
        )
        (ok true)
    )
)

(define-read-only (get-contractor-profile (contractor principal))
    (map-get? ContractorProfiles contractor)
)

(define-read-only (get-contractor-rating (rating-id uint))
    (map-get? ContractorRatings rating-id)
)

(define-read-only (has-rated-milestone
        (contractor principal)
        (rater principal)
        (milestone-id uint)
    )
    (is-some (map-get? RatingHistory {
        contractor: contractor,
        rater: rater,
        milestone-id: milestone-id,
    }))
)

(define-read-only (is-contractor-blacklisted (contractor principal))
    (let ((profile (map-get? ContractorProfiles contractor)))
        (if (is-some profile)
            (get is-blacklisted (unwrap-panic profile))
            false
        )
    )
)

(define-read-only (get-contractor-rating-summary (contractor principal))
    (let ((profile (map-get? ContractorProfiles contractor)))
        (if (is-some profile)
            (let (
                    (p (unwrap-panic profile))
                    (avg-stars (/ (get average-rating p) u100))
                    (avg-decimal (mod (get average-rating p) u100))
                )
                (some {
                    contractor: contractor,
                    total-ratings: (get total-ratings p),
                    average-rating-raw: (get average-rating p),
                    average-stars: avg-stars,
                    average-decimal: avg-decimal,
                    is-blacklisted: (get is-blacklisted p),
                    last-update: (get last-rating-update p),
                    rating-status: (if (get is-blacklisted p)
                        "blacklisted"
                        (if (< (get average-rating p) u250)
                            "poor"
                            (if (>= (get average-rating p) u400)
                                "excellent"
                                "good"
                            )
                        )
                    ),
                })
            )
            none
        )
    )
)

(define-read-only (get-rating-system-stats)
    {
        total-ratings-submitted: (var-get rating-counter),
        current-blacklist-threshold: (var-get blacklist-threshold),
        threshold-in-stars: (/ (var-get blacklist-threshold) u100),
    }
)

(define-map MilestoneEvidence
    {
        milestone-id: uint,
        submitted-by: principal,
    }
    {
        uri: (string-utf8 200),
        note: (string-utf8 100),
        submitted-at: uint,
    }
)

(define-public (submit-milestone-evidence
        (milestone-id uint)
        (uri (string-utf8 200))
        (note (string-utf8 100))
    )
    (let (
            (milestone (unwrap! (map-get? Milestones milestone-id) err-invalid-milestone))
            (sender tx-sender)
            (timestamp burn-block-height)
        )
        (asserts! (not (get completed milestone)) err-already-approved)
        (map-set MilestoneEvidence {
            milestone-id: milestone-id,
            submitted-by: sender,
        } {
            uri: uri,
            note: note,
            submitted-at: timestamp,
        })
        (ok true)
    )
)

(define-read-only (get-milestone-evidence
        (milestone-id uint)
        (submitted-by principal)
    )
    (map-get? MilestoneEvidence {
        milestone-id: milestone-id,
        submitted-by: submitted-by,
    })
)
