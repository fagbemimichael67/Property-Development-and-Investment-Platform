;; Development Tracker Contract
;; Monitors construction progress, milestones, and development costs

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-PROPERTY-NOT-FOUND (err u301))
(define-constant ERR-MILESTONE-NOT-FOUND (err u302))
(define-constant ERR-INVALID-INPUT (err u303))
(define-constant ERR-MILESTONE-ALREADY-COMPLETE (err u304))
(define-constant ERR-CONTRACTOR-NOT-FOUND (err u305))
(define-constant ERR-EXPENSE-NOT-FOUND (err u306))
(define-constant ERR-INSUFFICIENT-BUDGET (err u307))

;; Data Variables
(define-data-var next-expense-id uint u1)
(define-data-var next-contractor-id uint u1)

;; Data Maps
(define-map development-progress
  { property-id: uint }
  {
    current-phase: (string-ascii 32),
    completion-percentage: uint,
    total-budget: uint,
    spent-amount: uint,
    remaining-budget: uint,
    start-date: uint,
    estimated-completion: uint,
    actual-completion: (optional uint),
    last-updated: uint
  }
)

(define-map milestone-progress
  { property-id: uint, milestone-id: uint }
  {
    title: (string-ascii 128),
    description: (string-ascii 256),
    phase: (string-ascii 32),
    budget-allocated: uint,
    actual-cost: uint,
    completion-percentage: uint,
    start-date: (optional uint),
    target-completion: uint,
    actual-completion: (optional uint),
    status: (string-ascii 32),
    contractor-id: (optional uint),
    verification-hash: (optional (string-ascii 128))
  }
)

(define-map contractors
  { contractor-id: uint }
  {
    name: (string-ascii 128),
    contact-info: (string-ascii 256),
    specialization: (string-ascii 64),
    rating: uint,
    total-projects: uint,
    is-verified: bool,
    registered-date: uint
  }
)

(define-map contractor-assignments
  { property-id: uint, contractor-id: uint }
  {
    assigned-date: uint,
    role: (string-ascii 64),
    contract-value: uint,
    payment-schedule: (string-ascii 128),
    is-active: bool
  }
)

(define-map development-expenses
  { expense-id: uint }
  {
    property-id: uint,
    milestone-id: (optional uint),
    contractor-id: (optional uint),
    category: (string-ascii 64),
    description: (string-ascii 256),
    amount: uint,
    expense-date: uint,
    payment-status: (string-ascii 32),
    receipt-hash: (optional (string-ascii 128)),
    approved-by: (optional principal),
    created-at: uint
  }
)

(define-map budget-allocations
  { property-id: uint, category: (string-ascii 64) }
  {
    allocated-amount: uint,
    spent-amount: uint,
    remaining-amount: uint,
    last-updated: uint
  }
)

;; Authorization Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-property-developer (property-id uint))
  ;; This would typically check with property-registry contract
  ;; For now, we'll assume the caller has proper authorization
  true
)

;; Development Progress Functions
(define-public (initialize-development
  (property-id uint)
  (total-budget uint)
  (estimated-completion uint)
)
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-property-developer property-id) ERR-NOT-AUTHORIZED)
    (asserts! (> total-budget u0) ERR-INVALID-INPUT)
    (asserts! (> estimated-completion current-time) ERR-INVALID-INPUT)

    (map-set development-progress
      { property-id: property-id }
      {
        current-phase: "planning",
        completion-percentage: u0,
        total-budget: total-budget,
        spent-amount: u0,
        remaining-budget: total-budget,
        start-date: current-time,
        estimated-completion: estimated-completion,
        actual-completion: none,
        last-updated: current-time
      }
    )

    (ok true)
  )
)

(define-public (update-development-phase
  (property-id uint)
  (new-phase (string-ascii 32))
  (completion-percentage uint)
)
  (let
    (
      (progress-data (unwrap! (map-get? development-progress { property-id: property-id }) ERR-PROPERTY-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-property-developer property-id) ERR-NOT-AUTHORIZED)
    (asserts! (<= completion-percentage u10000) ERR-INVALID-INPUT) ;; Max 100%

    (map-set development-progress
      { property-id: property-id }
      (merge progress-data {
        current-phase: new-phase,
        completion-percentage: completion-percentage,
        last-updated: current-time,
        actual-completion: (if (is-eq completion-percentage u10000) (some current-time) none)
      })
    )

    (ok true)
  )
)

;; Milestone Management Functions
(define-public (create-development-milestone
  (property-id uint)
  (milestone-id uint)
  (title (string-ascii 128))
  (description (string-ascii 256))
  (phase (string-ascii 32))
  (budget-allocated uint)
  (target-completion uint)
)
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-property-developer property-id) ERR-NOT-AUTHORIZED)
    (asserts! (> budget-allocated u0) ERR-INVALID-INPUT)
    (asserts! (> target-completion current-time) ERR-INVALID-INPUT)

    (map-set milestone-progress
      { property-id: property-id, milestone-id: milestone-id }
      {
        title: title,
        description: description,
        phase: phase,
        budget-allocated: budget-allocated,
        actual-cost: u0,
        completion-percentage: u0,
        start-date: none,
        target-completion: target-completion,
        actual-completion: none,
        status: "planned",
        contractor-id: none,
        verification-hash: none
      }
    )

    (ok true)
  )
)

(define-public (start-milestone
  (property-id uint)
  (milestone-id uint)
  (contractor-id (optional uint))
)
  (let
    (
      (milestone-data (unwrap! (map-get? milestone-progress { property-id: property-id, milestone-id: milestone-id }) ERR-MILESTONE-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-property-developer property-id) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status milestone-data) "planned") ERR-MILESTONE-ALREADY-COMPLETE)

    (map-set milestone-progress
      { property-id: property-id, milestone-id: milestone-id }
      (merge milestone-data {
        start-date: (some current-time),
        status: "in-progress",
        contractor-id: contractor-id
      })
    )

    (ok true)
  )
)

(define-public (complete-milestone
  (property-id uint)
  (milestone-id uint)
  (actual-cost uint)
  (verification-hash (string-ascii 128))
)
  (let
    (
      (milestone-data (unwrap! (map-get? milestone-progress { property-id: property-id, milestone-id: milestone-id }) ERR-MILESTONE-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-property-developer property-id) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status milestone-data) "in-progress") ERR-MILESTONE-ALREADY-COMPLETE)
    (asserts! (> actual-cost u0) ERR-INVALID-INPUT)

    (map-set milestone-progress
      { property-id: property-id, milestone-id: milestone-id }
      (merge milestone-data {
        actual-cost: actual-cost,
        completion-percentage: u10000,
        actual-completion: (some current-time),
        status: "completed",
        verification-hash: (some verification-hash)
      })
    )

    ;; Update overall development progress
    (let
      (
        (progress-data (unwrap-panic (map-get? development-progress { property-id: property-id })))
        (new-spent-amount (+ (get spent-amount progress-data) actual-cost))
        (new-remaining-budget (- (get remaining-budget progress-data) actual-cost))
      )
      (map-set development-progress
        { property-id: property-id }
        (merge progress-data {
          spent-amount: new-spent-amount,
          remaining-budget: new-remaining-budget,
          last-updated: current-time
        })
      )
    )

    (ok true)
  )
)

;; Contractor Management Functions
(define-public (register-contractor
  (name (string-ascii 128))
  (contact-info (string-ascii 256))
  (specialization (string-ascii 64))
)
  (let
    (
      (contractor-id (var-get next-contractor-id))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)

    (map-set contractors
      { contractor-id: contractor-id }
      {
        name: name,
        contact-info: contact-info,
        specialization: specialization,
        rating: u0,
        total-projects: u0,
        is-verified: false,
        registered-date: current-time
      }
    )

    (var-set next-contractor-id (+ contractor-id u1))

    (ok contractor-id)
  )
)

(define-public (assign-contractor
  (property-id uint)
  (contractor-id uint)
  (role (string-ascii 64))
  (contract-value uint)
  (payment-schedule (string-ascii 128))
)
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-property-developer property-id) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? contractors { contractor-id: contractor-id })) ERR-CONTRACTOR-NOT-FOUND)
    (asserts! (> contract-value u0) ERR-INVALID-INPUT)

    (map-set contractor-assignments
      { property-id: property-id, contractor-id: contractor-id }
      {
        assigned-date: current-time,
        role: role,
        contract-value: contract-value,
        payment-schedule: payment-schedule,
        is-active: true
      }
    )

    (ok true)
  )
)

;; Expense Management Functions
(define-public (record-expense
  (property-id uint)
  (milestone-id (optional uint))
  (contractor-id (optional uint))
  (category (string-ascii 64))
  (description (string-ascii 256))
  (amount uint)
  (receipt-hash (optional (string-ascii 128)))
)
  (let
    (
      (expense-id (var-get next-expense-id))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-property-developer property-id) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-INPUT)

    (map-set development-expenses
      { expense-id: expense-id }
      {
        property-id: property-id,
        milestone-id: milestone-id,
        contractor-id: contractor-id,
        category: category,
        description: description,
        amount: amount,
        expense-date: current-time,
        payment-status: "pending",
        receipt-hash: receipt-hash,
        approved-by: none,
        created-at: current-time
      }
    )

    (var-set next-expense-id (+ expense-id u1))

    (ok expense-id)
  )
)

(define-public (approve-expense (expense-id uint))
  (let
    (
      (expense-data (unwrap! (map-get? development-expenses { expense-id: expense-id }) ERR-EXPENSE-NOT-FOUND))
    )
    (asserts! (is-property-developer (get property-id expense-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get payment-status expense-data) "pending") ERR-INVALID-INPUT)

    (map-set development-expenses
      { expense-id: expense-id }
      (merge expense-data {
        payment-status: "approved",
        approved-by: (some tx-sender)
      })
    )

    (ok true)
  )
)

;; Budget Management Functions
(define-public (allocate-budget
  (property-id uint)
  (category (string-ascii 64))
  (allocated-amount uint)
)
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-property-developer property-id) ERR-NOT-AUTHORIZED)
    (asserts! (> allocated-amount u0) ERR-INVALID-INPUT)

    (map-set budget-allocations
      { property-id: property-id, category: category }
      {
        allocated-amount: allocated-amount,
        spent-amount: u0,
        remaining-amount: allocated-amount,
        last-updated: current-time
      }
    )

    (ok true)
  )
)

;; Read-Only Functions
(define-read-only (get-development-progress (property-id uint))
  (map-get? development-progress { property-id: property-id })
)

(define-read-only (get-milestone-progress (property-id uint) (milestone-id uint))
  (map-get? milestone-progress { property-id: property-id, milestone-id: milestone-id })
)

(define-read-only (get-contractor (contractor-id uint))
  (map-get? contractors { contractor-id: contractor-id })
)

(define-read-only (get-contractor-assignment (property-id uint) (contractor-id uint))
  (map-get? contractor-assignments { property-id: property-id, contractor-id: contractor-id })
)

(define-read-only (get-expense (expense-id uint))
  (map-get? development-expenses { expense-id: expense-id })
)

(define-read-only (get-budget-allocation (property-id uint) (category (string-ascii 64)))
  (map-get? budget-allocations { property-id: property-id, category: category })
)

(define-read-only (calculate-completion-percentage (property-id uint))
  (match (map-get? development-progress { property-id: property-id })
    progress-data (get completion-percentage progress-data)
    u0
  )
)

(define-read-only (get-remaining-budget (property-id uint))
  (match (map-get? development-progress { property-id: property-id })
    progress-data (get remaining-budget progress-data)
    u0
  )
)
