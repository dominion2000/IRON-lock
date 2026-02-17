# IRON-lock

Decentralized Escrow Marketplace Smart Contract for the Stacks Blockchain.

---

## Overview

IRON-lock is a Clarity smart contract that enables secure escrow transactions between buyers and sellers, with optional arbitration and automated refunds. The contract manages funds, deadlines, and dispute resolution in a decentralized manner.

---

## Features

- **Escrow Creation:** Buyers initiate escrow with sellers and arbiters.
- **Delivery Confirmation:** Both buyer and seller must confirm delivery.
- **Dispute Resolution:** Arbiters can resolve disputes and allocate funds.
- **Automated Refunds:** Refunds are triggered if deadlines are missed.
- **Fee Management:** Platform and arbiter fees are calculated and distributed.

---

## Contract Details

- **Escrow States:** Pending, Disputed, Released, Refunded
- **Fee Structure:** Platform fee (0.5%), Arbiter fee (up to 10%)
- **Security:** Prevents self-trade, validates participant roles, and ensures proper state transitions.

---

## Usage

### Deployment

1. Clone this repository.
2. Deploy `IRON-lock.clar` using [Clarinet](https://github.com/hirosystems/clarinet) or your preferred Stacks development tool.

### Main Functions

- `create-escrow(seller, arbiter, amount, arbiter-fee-bps, duration, start-block)`
- `confirm-delivery(escrow-id)`
- `raise-dispute(escrow-id)`
- `resolve-dispute(escrow-id, favour)`
- `auto-refund(escrow-id, current-block)`

### Example

```lisp
(create-escrow 'ST2...seller 'ST3...arbiter u100000 u500 u144 u1000)
```

---

## Development

- Written in Clarity 1.x for Stacks blockchain.
- See `contracts/IRON-lock.clar` for implementation details.

