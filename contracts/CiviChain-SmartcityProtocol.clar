;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CiviChain v2 - Smart City Feedback Protocol
;; Professional Full Version
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ==============================
;; CONSTANTS
;; ==============================

(define-constant STATUS-OPEN u0)
(define-constant STATUS-INPROGRESS u1)
(define-constant STATUS-RESOLVED u2)

(define-constant ERR-NOT-FOUND u100)
(define-constant ERR-ALREADY-VOTED u101)
(define-constant ERR-NOT-AUTHORIZED u102)
(define-constant ERR-INVALID-STATUS u103)
(define-constant ERR-INVALID-FEE u104)

;; Optional anti-spam submission fee (in microSTX)
(define-constant SUBMISSION-FEE u1000000) ;; 1 STX

;; ==============================
;; DATA VARIABLES
;; ==============================

(define-data-var issue-counter uint u0)
(define-data-var admin principal tx-sender)

;; Reward pool balance
(define-data-var reward-pool uint u0)

;; ==============================
;; DATA MAPS
;; ==============================

(define-map issues
  { id: uint }
  {
    reporter: principal,
    category: (string-ascii 50),
    description: (string-ascii 200),
    votes: uint,
    status: uint,
    timestamp: uint
  }
)

(define-map votes
  { issue-id: uint, voter: principal }
  { voted: bool }
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; INTERNAL HELPER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-private (is-valid-status (status uint))
  (or
    (is-eq status STATUS-OPEN)
    (is-eq status STATUS-INPROGRESS)
    (is-eq status STATUS-RESOLVED)
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; PUBLIC FUNCTIONS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; --------------------------------
;; Submit Issue (With STX Fee)
;; --------------------------------
(define-public (submit-issue
    (category (string-ascii 50))
    (description (string-ascii 200))
  )
  (if (is-eq (len category) u0)
    (err ERR-INVALID-STATUS)
    (if (is-eq (len description) u0)
      (err ERR-INVALID-STATUS)
      (let (
            (id (+ (var-get issue-counter) u1))
           )
        (begin
          ;; Require fee payment
          (try! (stx-transfer? SUBMISSION-FEE tx-sender (as-contract tx-sender)))

          ;; Add fee to reward pool
          (var-set reward-pool (+ (var-get reward-pool) SUBMISSION-FEE))

          (map-set issues
            { id: id }
            {
              reporter: tx-sender,
              category: category,
              description: description,
              votes: u0,
              status: STATUS-OPEN,
              timestamp: u0
            }
          )

          (var-set issue-counter id)

          (ok id)
        )
      )
    )
  )
)

;; --------------------------------
;; Vote Issue (1 per wallet)
;; --------------------------------
(define-public (vote-issue (id uint))
  (let (
        (issue (map-get? issues { id: id }))
        (already-voted (map-get? votes { issue-id: id, voter: tx-sender }))
       )
    (if (is-none issue)
      (err ERR-NOT-FOUND)
      (if (is-some already-voted)
        (err ERR-ALREADY-VOTED)
        (begin
          (map-set votes
            { issue-id: id, voter: tx-sender }
            { voted: true }
          )
          (match issue data
            (begin
              (map-set issues
                { id: id }
                {
                  reporter: (get reporter data),
                  category: (get category data),
                  description: (get description data),
                  votes: (+ (get votes data) u1),
                  status: (get status data),
                  timestamp: (get timestamp data)
                }
              )
              (ok true)
            )
            (err ERR-NOT-FOUND)
          )
        )
      )
    )
  )
)

;; --------------------------------
;; Update Issue Status (Admin Only)
;; --------------------------------
(define-public (update-status (id uint) (new-status uint))
  (let (
        (issue (map-get? issues { id: id }))
       )
    (if (not (is-eq tx-sender (var-get admin)))
      (err ERR-NOT-AUTHORIZED)
      (if (is-none issue)
        (err ERR-NOT-FOUND)
        (if (not (is-valid-status new-status))
          (err ERR-INVALID-STATUS)
          (match issue data
            (begin
              (map-set issues
                { id: id }
                {
                  reporter: (get reporter data),
                  category: (get category data),
                  description: (get description data),
                  votes: (get votes data),
                  status: new-status,
                  timestamp: (get timestamp data)
                }
              )
              (ok true)
            )
            (err ERR-NOT-FOUND)
          )
        )
      )
    )
  )
)

;; --------------------------------
;; Reward Reporter (Admin Only)
;; --------------------------------
(define-public (reward-reporter (id uint) (amount uint))
  (let (
        (issue (map-get? issues { id: id }))
       )
    (if (not (is-eq tx-sender (var-get admin)))
      (err ERR-NOT-AUTHORIZED)
      (if (is-none issue)
        (err ERR-NOT-FOUND)
        (if (> amount (var-get reward-pool))
          (err ERR-INVALID-FEE)
          (match issue data
            (begin
              (try!
                (stx-transfer?
                  amount
                  (as-contract tx-sender)
                  (get reporter data)
                )
              )
              (var-set reward-pool (- (var-get reward-pool) amount))
              (ok true)
            )
            (err ERR-NOT-FOUND)
          )
        )
      )
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; READ ONLY FUNCTIONS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-read-only (get-issue (id uint))
  (map-get? issues { id: id })
)

(define-read-only (get-total-issues)
  (var-get issue-counter)
)

(define-read-only (get-reward-pool)
  (var-get reward-pool)
)

(define-read-only (get-admin)
  (var-get admin)
)
