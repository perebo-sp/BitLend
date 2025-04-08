;; BitLend: Bitcoin-Secured Decentralized Lending
;; 
;; Summary: A non-custodial lending protocol leveraging Bitcoin collateral through Stacks Layer 2
;;          for secure, transparent stablecoin loans with automatic risk management.

;; Description:
;; BitLend enables users to participate in decentralized finance while maintaining Bitcoin exposure.
;; Built on Stacks L2 for Bitcoin-native compliance, the protocol features:
;; - BTC over-collateralization (125% minimum ratio)
;; - Dynamic interest rates with 5% base APR
;; - Automated liquidations with 10% penalty
;; - Real-time price feeds via oracle integration
;; - sBTC-compatible collateral management
;; - Transparent debt tracking with continuous interest accrual
;; 
;; The protocol maintains Bitcoin's security guarantees while enabling sophisticated DeFi primitives
;; through Clarity's predictable smart contract language. All operations are verifiable on-chain
;; with Stacks' Bitcoin-anchored transactions.

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-collateral (err u101))
(define-constant err-too-much-debt (err u102))
(define-constant err-not-borrower (err u103))
(define-constant err-not-enough-funds (err u104))
(define-constant err-collateral-below-threshold (err u105))
(define-constant err-no-open-loan (err u106))
(define-constant err-not-liquidatable (err u107))
(define-constant err-already-initialized (err u108))
(define-constant err-not-initialized (err u109))

;; 80% - collateral must be 125% of loan value
(define-constant liquidation-threshold u800000)
;; 70% - can only borrow up to 70% of collateral value
(define-constant loan-to-value-ratio u700000)
;; 5% APR (in basis points: 500 = 5%)
(define-constant base-interest-rate u500)
;; 10% liquidation penalty (in basis points: 1000 = 10%)
(define-constant liquidation-penalty u1000)
;; 100% represents 1 in fixed-point calculations (6 decimal places)
(define-constant fixed-point-factor u1000000)

;; Data vars
(define-data-var initialized bool false)
(define-data-var total-collateral uint u0)
(define-data-var total-borrowed uint u0)
(define-data-var last-accrual-time uint u0)

;; Price oracle data - would be updated by an oracle service
(define-data-var btc-price-in-usd uint u0)

;; Maps
;; User's collateral balance
(define-map user-collateral principal uint)

;; User's borrowed balance
(define-map user-borrowed principal uint)

;; Tracks when interest was last accrued for a user
(define-map user-last-accrual principal uint)

;; Read-only functions

;; Get user collateral
(define-read-only (get-user-collateral (user principal))
  (default-to u0 (map-get? user-collateral user))
)

;; Get user borrowed amount
(define-read-only (get-user-borrowed (user principal))
  (default-to u0 (map-get? user-borrowed user))
)

;; Get current BTC price
(define-read-only (get-btc-price)
  (var-get btc-price-in-usd)
)

;; Calculate user health factor
;; Health factor = (collateral-value * fixed-point) / (borrowed-value * liquidation-threshold)
;; If health factor < 1.0 (fixed-point), loan can be liquidated
(define-read-only (get-health-factor (user principal))
  (let (
    (collateral (get-user-collateral user))
    (borrowed (get-user-borrowed user))
    (btc-price (var-get btc-price-in-usd))
  )
    (if (is-eq borrowed u0)
      (ok u0) ;; No loan, return 0
      (let (
        (collateral-value (* collateral btc-price))
        (collateral-value-scaled (* collateral-value fixed-point-factor))
        (borrowed-threshold-value (* borrowed liquidation-threshold))
      )
        (ok (/ collateral-value-scaled borrowed-threshold-value))
      )
    )
  )
)

;; Calculate maximum borrowable amount for a user
(define-read-only (get-max-borrowable (user principal))
  (let (
    (collateral (get-user-collateral user))
    (btc-price (var-get btc-price-in-usd))
  )
    (/ (* collateral btc-price loan-to-value-ratio) fixed-point-factor)
  )
)

;; Check if a loan can be liquidated
(define-read-only (can-liquidate? (user principal))
  (let (
    (health-factor-response (get-health-factor user))
  )
    (if (is-ok health-factor-response)
      (let (
        (health-factor (unwrap-panic health-factor-response))
      )
        (< health-factor fixed-point-factor)
      )
      false
    )
  )
)

;; Calculate interest accrued for a user
(define-read-only (calculate-interest (user principal))
  (let (
    (borrowed (get-user-borrowed user))
    (last-accrual (default-to u0 (map-get? user-last-accrual user)))
    (current-block (unwrap-panic (get-block-info? time (- block-height u1))))
    (time-elapsed (if (is-eq last-accrual u0)
                     u0
                     (- current-block last-accrual)))
  )
    ;; Simple interest calculation: borrowed * rate * time / (100% * seconds-in-year)
    ;; Rate is in basis points (1/100 of a percent)
    ;; We use 31536000 for seconds in a year (365 days)
    (if (is-eq time-elapsed u0)
      u0
      (/ (* (* borrowed base-interest-rate) time-elapsed) (* fixed-point-factor u31536000))
    )
  )
)

;; Public functions

;; Initialize the contract with a BTC price
(define-public (initialize (initial-btc-price uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get initialized)) err-already-initialized)
    
    (var-set btc-price-in-usd initial-btc-price)
    (var-set initialized true)
    (var-set last-accrual-time (unwrap-panic (get-block-info? time (- block-height u1))))
    
    (ok true)
  )
)

;; Update the BTC price (would be called by an oracle)
(define-public (update-btc-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (var-get initialized) err-not-initialized)
    
    (var-set btc-price-in-usd new-price)
    (ok true)
  )
)

;; Deposit collateral (BTC)
;; In a real implementation, this would integrate with sBTC or another Bitcoin representation
(define-public (deposit-collateral (amount uint))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    
    ;; In a real implementation, there would be an actual token transfer here
    ;; This is a simplified version
    (let (
      (current-collateral (get-user-collateral tx-sender))
    )
      (map-set user-collateral tx-sender (+ current-collateral amount))
      (var-set total-collateral (+ (var-get total-collateral) amount))
      
      (ok true)
    )
  )
)

;; Withdraw collateral
(define-public (withdraw-collateral (amount uint))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    
    (let (
      (current-collateral (get-user-collateral tx-sender))
      (current-borrowed (get-user-borrowed tx-sender))
    )
      ;; Check if user has enough collateral
      (asserts! (>= current-collateral amount) err-not-enough-funds)
      
      ;; If user has an outstanding loan, need to check health factor after withdrawal
      (if (> current-borrowed u0)
        (let (
          (new-collateral (- current-collateral amount))
          (btc-price (var-get btc-price-in-usd))
          (collateral-value (* new-collateral btc-price))
          (min-collateral-needed (/ (* current-borrowed fixed-point-factor) loan-to-value-ratio))
        )
          ;; Ensure enough collateral remains
          (asserts! (>= collateral-value min-collateral-needed) err-collateral-below-threshold)
          
          ;; Update state
          (map-set user-collateral tx-sender new-collateral)
          (var-set total-collateral (- (var-get total-collateral) amount))
          
          ;; In a real implementation, there would be an actual token transfer here
          (ok true)
        )
        (begin
          ;; No loan, just withdraw
          (map-set user-collateral tx-sender (- current-collateral amount))
          (var-set total-collateral (- (var-get total-collateral) amount))
          
          ;; In a real implementation, there would be an actual token transfer here
          (ok true)
        )
      )
    )
  )
)

;; Borrow stablecoins against collateral
(define-public (borrow (amount uint))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    
    (let (
      (max-borrowable (get-max-borrowable tx-sender))
      (current-borrowed (get-user-borrowed tx-sender))
      (accrued-interest (calculate-interest tx-sender))
      (total-debt (+ current-borrowed accrued-interest))
      (new-total-debt (+ total-debt amount))
    )
      ;; Check if borrowing is within limits
      (asserts! (<= new-total-debt max-borrowable) err-too-much-debt)
      
      ;; Update user's debt with interest and new borrowed amount
      (map-set user-borrowed tx-sender new-total-debt)
      (map-set user-last-accrual tx-sender (unwrap-panic (get-block-info? time (- block-height u1))))
      
      ;; Update global state
      (var-set total-borrowed (+ (var-get total-borrowed) amount))
      
      ;; In a real implementation, there would be an actual token transfer here
      (ok true)
    )
  )
)

;; Repay loan (partially or fully)
(define-public (repay (amount uint))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    
    (let (
      (current-borrowed (get-user-borrowed tx-sender))
      (accrued-interest (calculate-interest tx-sender))
      (total-debt (+ current-borrowed accrued-interest))
    )
      ;; Check if user has a loan
      (asserts! (> total-debt u0) err-no-open-loan)
      
      ;; Determine how much to repay (cap at total debt)
      (let (
        (amount-to-repay (if (> amount total-debt) total-debt amount))
        (remaining-debt (- total-debt amount-to-repay))
      )
        ;; Update user's debt
        (map-set user-borrowed tx-sender remaining-debt)
        (map-set user-last-accrual tx-sender (unwrap-panic (get-block-info? time (- block-height u1))))
        
        ;; Update global state
        (var-set total-borrowed (- (var-get total-borrowed) amount-to-repay))
        
        ;; In a real implementation, there would be an actual token transfer here
        (ok true)
      )
    )
  )
)