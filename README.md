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

When the timer ends, **anyone** can call `settleLeague`. The contract reads each picked wallet's full portfolio value — native ETH, WBTC, USDC, and every other registered token — prices them via DEX pairs, and compares to the snapshot from league start. Best % gain wins. **No oracles. No reporters. Just math on chain.**

Let's say Alice's whale went from $90k → $150k (+67%) while Bob's degen went $90k → $100k (+11%). Alice wins.

**5. Payout**
- Total pot: 200 CLAWD
- House cut (5%): 10 CLAWD → **burned to 0xdead** 🔥
- Alice claims: **190 CLAWD**
- Bob gets: nothing. Better luck next time.

### Where Do Players Find Wallets?

Players scout wallets on their own — that's part of the skill. Tools like [DeBank](https://debank.com), [Arkham](https://www.arkham.com), [Nansen](https://nansen.ai), or just following Crypto Twitter for alpha on top traders. Find a wallet, paste the address, bet on it.

### Safety Nets

- **Stale leagues**: If a league never fills after 7 days, anyone can cancel it → full refunds.
- **No settlement**: If nobody settles within 24 hours after a league ends, it can be cancelled → full refunds.

---

## Architecture: Fully Onchain Portfolio Valuation

The key design decision: **no oracles, no offchain reporters.** The contract reads all balances and prices directly from the chain at the moment of settlement.

### Token Registry

The contract owner maintains a registry of tracked tokens. Each entry contains:

| Field | Description |
|-------|-------------|
| `token` | ERC-20 address |
| `pair` | Uniswap V2-style pair address (any DEX with `getReserves()`) |
| `isToken0` | Whether this token is `token0` in the pair |
| `decimals` | Token decimals |
| `pairedWithETH` | `true` = pair is token/WETH, `false` = pair is token/USDC |

Example setup for Base:
```
addToken(WBTC,  wbtcUsdcPair,  true,  8,  false)  // WBTC priced via USDC pair
addToken(LINK,  linkEthPair,   true,  18, true)    // LINK priced via ETH pair
addToken(AERO,  aeroUsdcPair,  true,  18, false)   // AERO priced via USDC pair
addToken(cbETH, cbEthEthPair,  true,  18, true)    // cbETH priced via ETH pair
```

Native ETH is always tracked (priced via a configurable WETH/USDC pair).

### Portfolio Valuation Flow

When `getPortfolioValue(wallet)` is called:

1. **Native ETH**: `wallet.balance` × ETH price from WETH/USDC pair reserves
2. **Each registered token**: `token.balanceOf(wallet)` × price from its DEX pair reserves
3. **Sum everything** → total value in USDC (18-decimal fixed point)

For ETH-paired tokens, the price is converted through two hops: token → ETH → USDC.

### Settlement Math

```
startValue = snapshot taken when league starts (sum of all token values)
endValue   = portfolio value at time of settlement

score = (endValue - startValue) / startValue × 10000  (basis points)
```

If a player has multiple picks, their score is the **average across all picks**. Ties split the pot evenly.

### What This Catches

- ✅ Wallet swaps ETH for WBTC → WBTC balance goes up, ETH goes down, net value tracked
- ✅ Wallet accumulates USDC from sells → USDC balance counted
- ✅ Token prices move → reserves in the pair change, new price reflected at settlement
- ✅ Wallet does nothing → score is 0 (or changes if token prices move)

### What This Doesn't Catch

- ❌ Tokens not in the registry (owner needs to add them)
- ❌ LP positions, staked tokens, or tokens locked in DeFi protocols
- ❌ NFTs or non-fungible assets
- ❌ Cross-chain activity

This is a known tradeoff: we track a curated set of major tokens rather than trying to value everything. For most active traders on Base, the registered tokens will cover the bulk of their portfolio.

### Price Manipulation Risk

Since prices come from DEX pair reserves, a large swap could temporarily skew the price at the moment of settlement. Mitigations:
- Use high-liquidity pairs (Uniswap V2, Aerodrome)
- The entry fee makes manipulation uneconomical for small leagues
- Future improvement: TWAP (time-weighted average price) instead of spot price

---

## Contract API

### Owner Functions
| Function | Description |
|----------|-------------|
| `setEthUsdcPair(pair, ethIsToken0)` | Set the WETH/USDC pair for ETH pricing |
| `addToken(token, pair, isToken0, decimals, pairedWithETH)` | Add a token to the registry |
| `removeToken(index)` | Remove a token from the registry |

### Player Functions
| Function | Description |
|----------|-------------|
| `createLeague(fee, duration, maxPlayers, maxPicks, houseCutBps, picks)` | Create a league and join with your picks |
| `joinLeague(leagueId, picks)` | Join an existing league |
| `startLeague(leagueId)` | Creator can start early (needs 2+ players) |
| `settleLeague(leagueId)` | Anyone can settle after timer ends |
| `claimWinnings(leagueId)` | Winner claims their share |
| `cancelLeague(leagueId)` | Cancel stale/unsettled leagues |
| `claimRefund(leagueId)` | Refund on cancelled leagues |

### View Functions
| Function | Description |
|----------|-------------|
| `getPortfolioValue(wallet)` | Get total portfolio value in USDC (18 dec) |
| `getPlayerScore(leagueId, player)` | Get player's current score in basis points |
| `getETHPrice()` | Get current ETH price in USDC |
| `getEntries(leagueId)` | Get all entries for a league |
| `getWinners(leagueId)` | Get winners of a settled league |

---

## What's Built

- ✅ **Smart contract** — `FantasyLeague.sol`, 24/24 tests passing (ReentrancyGuard, SafeERC20, CEI)
- ✅ **Portfolio valuation** — Onchain token balances + DEX pair prices, no oracles
- ✅ **Frontend** — League browser, create form, league detail with join/settle/claim flows
- ✅ **Token burns** — House cut burned to `0xdead` on every settlement
- ✅ **Mock infrastructure** — `MockV2Pair` + `MockERC20` for full local testing

## What's Next

- ⬜ **Live score UI** — `getPlayerScore()` exists in the contract, needs frontend display
- ⬜ **Token registry setup for Base** — Register WETH, USDC, WBTC, cbETH, AERO pairs
- ⬜ **Production deployment** — Deploy to Base mainnet
- ⬜ **TWAP pricing** — Time-weighted prices to resist manipulation
- ⬜ **Popular picks leaderboard** — Show which wallets are being picked most

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

- **Contracts**: Solidity 0.8.19, Foundry, OpenZeppelin
- **Pricing**: Uniswap V2-style `getReserves()` (works with Aerodrome, SushiSwap, etc.)
- **Frontend**: Next.js, RainbowKit, Wagmi, Viem
- **Token**: $CLAWD on Base (`0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07`)
- **Framework**: [Scaffold-ETH 2](https://scaffoldeth.io)

## Tests

```bash
cd packages/foundry
forge test -vv
```

24 tests covering: portfolio valuation, token price changes, mixed portfolio swaps, settlement edge cases, ties, cancellation, refunds, and fuzz testing.
