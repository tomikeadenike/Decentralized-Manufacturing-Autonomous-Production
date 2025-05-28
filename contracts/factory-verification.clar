;; Factory Verification Contract
;; Validates autonomous manufacturing facilities

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_FACTORY_NOT_FOUND (err u101))
(define-constant ERR_FACTORY_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_STATUS (err u103))

;; Factory status types
(define-constant STATUS_PENDING u0)
(define-constant STATUS_VERIFIED u1)
(define-constant STATUS_SUSPENDED u2)
(define-constant STATUS_REVOKED u3)

;; Factory data structure
(define-map factories
  { factory-id: uint }
  {
    owner: principal,
    name: (string-ascii 64),
    location: (string-ascii 128),
    capacity: uint,
    status: uint,
    verification-date: uint,
    certifications: (list 10 (string-ascii 32))
  }
)

;; Factory counter
(define-data-var factory-counter uint u0)

;; Authorized verifiers
(define-map verifiers principal bool)

;; Initialize contract owner as verifier
(map-set verifiers CONTRACT_OWNER true)

;; Register a new factory
(define-public (register-factory
  (name (string-ascii 64))
  (location (string-ascii 128))
  (capacity uint)
  (certifications (list 10 (string-ascii 32))))
  (let ((factory-id (+ (var-get factory-counter) u1)))
    (asserts! (is-none (map-get? factories { factory-id: factory-id })) ERR_FACTORY_ALREADY_EXISTS)
    (map-set factories
      { factory-id: factory-id }
      {
        owner: tx-sender,
        name: name,
        location: location,
        capacity: capacity,
        status: STATUS_PENDING,
        verification-date: u0,
        certifications: certifications
      })
    (var-set factory-counter factory-id)
    (ok factory-id)))

;; Verify a factory (only authorized verifiers)
(define-public (verify-factory (factory-id uint))
  (let ((factory (unwrap! (map-get? factories { factory-id: factory-id }) ERR_FACTORY_NOT_FOUND)))
    (asserts! (default-to false (map-get? verifiers tx-sender)) ERR_UNAUTHORIZED)
    (map-set factories
      { factory-id: factory-id }
      (merge factory {
        status: STATUS_VERIFIED,
        verification-date: block-height
      }))
    (ok true)))

;; Update factory status
(define-public (update-factory-status (factory-id uint) (new-status uint))
  (let ((factory (unwrap! (map-get? factories { factory-id: factory-id }) ERR_FACTORY_NOT_FOUND)))
    (asserts! (default-to false (map-get? verifiers tx-sender)) ERR_UNAUTHORIZED)
    (asserts! (<= new-status STATUS_REVOKED) ERR_INVALID_STATUS)
    (map-set factories
      { factory-id: factory-id }
      (merge factory { status: new-status }))
    (ok true)))

;; Add verifier (only contract owner)
(define-public (add-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set verifiers verifier true)
    (ok true)))

;; Get factory details
(define-read-only (get-factory (factory-id uint))
  (map-get? factories { factory-id: factory-id }))

;; Check if factory is verified
(define-read-only (is-factory-verified (factory-id uint))
  (match (map-get? factories { factory-id: factory-id })
    factory (is-eq (get status factory) STATUS_VERIFIED)
    false))

;; Get total factories
(define-read-only (get-factory-count)
  (var-get factory-counter))
