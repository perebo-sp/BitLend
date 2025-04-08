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