# 🦞 CLAWD Fantasy — Deployment Status

## Contract (Base Mainnet) ✅ LIVE

**FantasyLeague:** `0x54659613dc56fF779B799073b231785F473B3D99`  
**Network:** Base (chainId 8453)  
**CLAWD Token:** `0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07`  
**Owner/Deployer:** `0x4f8ac2faa3cacacacb7b4997a48f377fe88dfd46` (clawd-crash-deployer keystore)  
**Deployed:** 2026-02-19  
**Leagues created:** 0 (fresh)  

### Contract Architecture

Single `FantasyLeague.sol` manages all leagues via mappings. No per-league deploys.

- `createLeague()` — creator picks wallets + sets entry fee, duration, max players
- `joinLeague()` — players pick wallets + pay entry fee in $CLAWD
- `startLeague()` — auto-starts when full, or creator can manually start with 2+ players
- `reportResults()` — owner calls with winner addresses after duration ends
- `claimWinnings()` — winners pull funds after 1h dispute window
- `cancelLeague()` — creator can cancel stale leagues (refunds all)
- `claimRefund()` — players pull refunds from cancelled leagues

House cut (0-10%, configurable per league) is burned to `0x000...dead`.

### Token Registry (NEEDED BEFORE GO-LIVE)

The contract uses an onchain token registry + Uniswap V2 pairs to value wallets.  
**Before creating a real league, the owner must call:**

1. `setEthUsdcPair(pair, isToken0)` — WETH/USDC pair on Base for ETH pricing
2. `addToken(token, pair, isToken0, decimals, pairedWithETH)` — for each tradeable token

**Base Uniswap V2-style pairs to add (TODO):**
- ETH: native (address(0)), needs ETH/USDC pair address
- WBTC, cbBTC, etc. — find via Uniswap V2 factory or Aerodrome

Until the token registry is populated, picks must be wallet addresses — results are **reported manually by the owner**.

### Results Reporting

The contract owner calls `reportResults(leagueId, winners[])` to settle a league.  
For the MVP, this is **manual** — Austin or rightclaw checks wallet performance and calls it.  
Future: automate via a cron/oracle that reads onchain balances at league end.

---

## Frontend

**Dev:** `yarn start` → http://localhost:3000  
**Target network:** Base mainnet  
**Wallet:** RainbowKit (MetaMask, Coinbase, WalletConnect — no burner wallet)

### Pages
- `/` — League browser (filter by status, create button)
- `/create` — Create a league (entry fee, duration, max players, wallet picks)
- `/league/[id]` — League detail, join, countdown, claim, dispute
- `/debug` — SE2 debug panel for direct contract interaction

---

## Work Done (2026-02-19 to 2026-02-22)

### Phase 1 — Contracts ✅
- `FantasyLeague.sol` — full game logic with SafeERC20, ReentrancyGuard, CEI pattern
- `MockERC20.sol` — for local testing
- 18/18 tests passing (unit + fuzz)
- Deploy script for Base mainnet (`DeployFantasyLeagueBase.s.sol`)
- Deployed to Base mainnet

### Phase 2 — Frontend ✅
- SE2 (Next.js 15, wagmi, RainbowKit) scaffold
- League browser with status filter tabs
- Create league form (entry fee, duration toggle, max players slider, wallet picker)
- League detail page (join flow, countdown timer, claim, dispute, refund)
- ThreeButtonFlow component (Switch Network → Approve CLAWD → Execute)
- `onlyLocalBurnerWallet: false` — real wallet connection enabled

### Phase 3 — Deploy & Test (IN PROGRESS 🔧)
- Contract is live on Base
- Frontend pointed at Base (scaffold.config.ts)
- **TODO:** Populate token registry (addToken calls) for onchain portfolio valuation
- **TODO:** Test full flow end-to-end with small CLAWD amounts
- **TODO:** Results reporting automation (or manual for MVP)
- **TODO:** Deploy frontend to IPFS + set ENS record

---

## Running Locally

```bash
# Install
yarn install

# Start frontend (points to Base mainnet)
yarn start
# → http://localhost:3000

# Run tests
cd packages/foundry
forge test -vv

# Deploy (needs DEPLOYER_PRIVATE_KEY in .env — never commit this)
forge script script/DeployFantasyLeagueBase.s.sol --rpc-url base --broadcast
```

## Environment Variables

Copy `packages/foundry/.env.example` → `packages/foundry/.env` and fill in:
- `ALCHEMY_API_KEY` — for RPC
- `ETHERSCAN_API_KEY` — for contract verification
- Never commit `.env` (it's gitignored)

---

## Known Issues / Decisions

1. **Token registry empty** — wallets with no registered tokens will show $0 value. Fine for MVP if results are reported manually.
2. **Results reporting is manual** — no oracle yet. Owner calls `reportResults` based on offchain data.
3. **1-hour dispute window** — players can dispute results; owner resolves. No automated dispute resolution.
4. **Crash game comparison** — Crash was archived because it needed a centralized commit/reveal operator. Fantasy avoids this — wallets are public data, anyone can verify results.
