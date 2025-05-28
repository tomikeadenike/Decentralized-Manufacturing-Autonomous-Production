;; Human Oversight Contract
;; Manages human-machine collaboration

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u500))
(define-constant ERR_ALERT_NOT_FOUND (err u501))
(define-constant ERR_INVALID_PRIORITY (err u502))
(define-constant ERR_INVALID_STATUS (err u503))

;; Alert priority levels
(define-constant PRIORITY_LOW u1)
(define-constant PRIORITY_MEDIUM u2)
(define-constant PRIORITY_HIGH u3)
(define-constant PRIORITY_CRITICAL u4)

;; Alert status types
(define-constant ALERT_OPEN u0)
(define-constant ALERT_ACKNOWLEDGED u1)
(define-constant ALERT_IN_PROGRESS u2)
(define-constant ALERT_RESOLVED u3)
(define-constant ALERT_ESCALATED u4)

;; Alert structure
(define-map alerts
  { alert-id: uint }
  {
    factory-id: uint,
    order-id: (optional uint),
    alert-type: (string-ascii 32),
    priority: uint,
    status: uint,
    description: (string-ascii 256),
    created-at: uint,
    assigned-to: (optional principal),
    resolved-at: uint,
    resolution-notes: (string-ascii 256)
  }
)

;; Alert counter
(define-data-var alert-counter uint u0)

;; Human operators
(define-map operators
  { operator: principal }
  {
    name: (string-ascii 64),
    specialization: (string-ascii 32),
    active: bool,
    alerts-handled: uint,
    average-resolution-time: uint
  }
)

;; Intervention logs
(define-map interventions
  { intervention-id: uint }
  {
    alert-id: uint,
    operator: principal,
    action-taken: (string-ascii 256),
    timestamp: uint,
    effectiveness: uint
  }
)

;; Intervention counter
(define-data-var intervention-counter uint u0)

;; Create alert
(define-public (create-alert
  (factory-id uint)
  (order-id (optional uint))
  (alert-type (string-ascii 32))
  (priority uint)
  (description (string-ascii 256)))
  (let ((alert-id (+ (var-get alert-counter) u1)))
    (asserts! (and (>= priority PRIORITY_LOW) (<= priority PRIORITY_CRITICAL)) ERR_INVALID_PRIORITY)

    (map-set alerts
      { alert-id: alert-id }
      {
        factory-id: factory-id,
        order-id: order-id,
        alert-type: alert-type,
        priority: priority,
        status: ALERT_OPEN,
        description: description,
        created-at: block-height,
        assigned-to: none,
        resolved-at: u0,
        resolution-notes: ""
      })

    (var-set alert-counter alert-id)
    (ok alert-id)))

;; Assign alert to operator
(define-public (assign-alert (alert-id uint) (operator principal))
  (let ((alert (unwrap! (map-get? alerts { alert-id: alert-id }) ERR_ALERT_NOT_FOUND)))
    (asserts! (is-some (map-get? operators { operator: operator })) ERR_UNAUTHORIZED)

    (map-set alerts
      { alert-id: alert-id }
      (merge alert {
        assigned-to: (some operator),
        status: ALERT_ACKNOWLEDGED
      }))
    (ok true)))

;; Update alert status
(define-public (update-alert-status (alert-id uint) (new-status uint))
  (let ((alert (unwrap! (map-get? alerts { alert-id: alert-id }) ERR_ALERT_NOT_FOUND)))
    (asserts! (or
      (is-eq tx-sender CONTRACT_OWNER)
      (is-eq (some tx-sender) (get assigned-to alert))) ERR_UNAUTHORIZED)
    (asserts! (<= new-status ALERT_ESCALATED) ERR_INVALID_STATUS)

    (let ((updated-alert (merge alert { status: new-status })))
      (let ((final-alert
        (if (is-eq new-status ALERT_RESOLVED)
          (merge updated-alert { resolved-at: block-height })
          updated-alert)))

        (map-set alerts { alert-id: alert-id } final-alert)
        (ok true)))))

;; Resolve alert
(define-public (resolve-alert (alert-id uint) (resolution-notes (string-ascii 256)))
  (let ((alert (unwrap! (map-get? alerts { alert-id: alert-id }) ERR_ALERT_NOT_FOUND)))
    (asserts! (is-eq (some tx-sender) (get assigned-to alert)) ERR_UNAUTHORIZED)

    (map-set alerts
      { alert-id: alert-id }
      (merge alert {
        status: ALERT_RESOLVED,
        resolved-at: block-height,
        resolution-notes: resolution-notes
      }))

    ;; Update operator stats
    (let ((operator-data (unwrap! (map-get? operators { operator: tx-sender }) ERR_UNAUTHORIZED)))
      (map-set operators
        { operator: tx-sender }
        (merge operator-data {
          alerts-handled: (+ (get alerts-handled operator-data) u1)
        })))

    (ok true)))

;; Log intervention
(define-public (log-intervention
  (alert-id uint)
  (action-taken (string-ascii 256))
  (effectiveness uint))
  (let ((intervention-id (+ (var-get intervention-counter) u1)))
    (let ((alert (unwrap! (map-get? alerts { alert-id: alert-id }) ERR_ALERT_NOT_FOUND)))
      (asserts! (is-eq (some tx-sender) (get assigned-to alert)) ERR_UNAUTHORIZED)

      (map-set interventions
        { intervention-id: intervention-id }
        {
          alert-id: alert-id,
          operator: tx-sender,
          action-taken: action-taken,
          timestamp: block-height,
          effectiveness: effectiveness
        })

      (var-set intervention-counter intervention-id)
      (ok intervention-id))))

;; Register operator
(define-public (register-operator
  (operator principal)
  (name (string-ascii 64))
  (specialization (string-ascii 32)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set operators
      { operator: operator }
      {
        name: name,
        specialization: specialization,
        active: true,
        alerts-handled: u0,
        average-resolution-time: u0
      })
    (ok true)))

;; Read-only functions
(define-read-only (get-alert (alert-id uint))
  (map-get? alerts { alert-id: alert-id }))

(define-read-only (get-operator (operator principal))
  (map-get? operators { operator: operator }))

(define-read-only (get-intervention (intervention-id uint))
  (map-get? interventions { intervention-id: intervention-id }))

(define-read-only (get-alert-count)
  (var-get alert-counter))

(define-read-only (get-intervention-count)
  (var-get intervention-counter))
