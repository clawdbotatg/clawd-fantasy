# 🦞 CLAWD Fantasy

**Fantasy sports, but for crypto wallets.** Pick the traders you think will win. Bet $CLAWD on it. Winner takes the pot.

Built on Base with [Scaffold-ETH 2](https://scaffoldeth.io).

## How It Works

Imagine fantasy football, but instead of picking NFL players, you pick **onchain wallet addresses** — traders you think will outperform everyone else's picks.

### Alice vs Bob: A User Journey

**1. Alice creates a league**

Alice thinks she's spotted a whale who's about to have a great day. She creates a league:
- Entry fee: 100 CLAWD
- Duration: 1 day
- Max players: 2 (head to head)
- Picks per player: 1
- House cut: 5%

She enters the wallet address of the trader she's betting on — `0xWhale123...` — and pays 100 CLAWD to enter. She's in.

**2. Bob joins**

Bob sees Alice's league on the home page. He's been watching a different degen who's been on a tear. He picks `0xDegen456...`, pays 100 CLAWD, and joins.

The league is full (2/2 players), so it **auto-starts**. The 24-hour clock begins.

**3. The clock runs**

For the next 24 hours, both wallets go about their business — trading, holding, farming, whatever they do onchain. Alice and Bob can't do anything but watch and sweat.

**4. Settlement**

When the timer ends, **anyone** can call `settleLeague`. The contract reads each picked wallet's current ETH balance, compares it to the snapshot from league start, and calculates the % change. Best % gain wins. No oracles. No reporters. Just math on chain.

Let's say Alice's whale went from 10 ETH → 15 ETH (+50%) while Bob's degen went 10 ETH → 12 ETH (+20%). Alice wins.

**5. Payout**
- Total pot: 200 CLAWD
- House cut (5%): 10 CLAWD → **burned to 0xdead** 🔥
- Alice claims: **190 CLAWD**
- Bob gets: nothing. Better luck next time.

### Safety Nets

- **Stale leagues**: If a league never fills after 7 days, anyone can cancel it and players get refunded.
- **Missing results**: If no results are submitted within 24 hours after a league ends, it can be cancelled for refunds.
- **Disputes**: Any player can dispute results within 1 hour. Disputed results are cleared and the reporter must resubmit.

## What's Built

- ✅ **Smart contract** — `FantasyLeague.sol` with 18/18 tests passing (ReentrancyGuard, SafeERC20, CEI pattern)
- ✅ **Frontend** — League browser, create form, league detail page with join/claim/dispute flows
- ✅ **Token burns** — House cut sent to 0xdead on every league settlement

## What's Missing

- ❌ **Live score UI** — The contract has `getPlayerScore()` to check scores mid-league, but the frontend doesn't show live performance yet.
- ❌ **Production deployment** — Currently local only.

## Quick Start

```bash
git clone https://github.com/clawdbotatg/clawd-fantasy.git
cd clawd-fantasy
yarn install
yarn chain    # Start local Anvil chain
yarn deploy   # Deploy contracts
yarn start    # Start frontend at http://localhost:3000
```

## Tech Stack

- **Contracts**: Solidity, Foundry, OpenZeppelin
- **Frontend**: Next.js, RainbowKit, Wagmi, Viem
- **Token**: $CLAWD on Base (`0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07`)
- **Framework**: [Scaffold-ETH 2](https://scaffoldeth.io)