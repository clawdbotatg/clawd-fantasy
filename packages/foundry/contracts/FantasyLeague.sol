// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

/// @title FantasyLeague — Fully onchain fantasy crypto betting
/// @notice Pick wallets you think will gain the most value. Settlement reads token balances
///         and DEX pair prices directly from the chain. No oracles.
contract FantasyLeague is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public clawd;
    uint256 public leagueCount;

    // ─── Token Registry ───
    struct TokenInfo {
        address token;      // ERC-20 address (address(0) = native ETH)
        address pair;       // V2-style pair (getReserves)
        bool isToken0;      // is this token token0 in the pair?
        uint8 decimals;     // token decimals
        bool pairedWithETH; // true = pair is token/WETH, false = pair is token/USDC
    }

    TokenInfo[] public tokenRegistry;
    address public ethUsdcPair;    // WETH/USDC pair for ETH price
    bool public ethIsToken0InPair; // is WETH token0 in the ETH/USDC pair?
    uint8 public usdcDecimals;     // USDC decimals (6)

    // ─── League Structs ───
    enum LeagueStatus { Created, Active, Settled, Cancelled }

    struct League {
        address creator;
        uint256 entryFee;
        uint256 duration;
        uint256 maxPlayers;
        uint256 maxPicks;
        uint256 startTime;
        uint256 endTime;
        uint256 totalPot;
        uint256 houseCutBps;
        LeagueStatus status;
        uint256 settledAt;
        uint256 createdAt;
    }

    struct Entry {
        address player;
        address[] picks;
        bool claimed;
    }

    mapping(uint256 => League) internal _leagues;
    mapping(uint256 => Entry[]) public entries;
    mapping(uint256 => mapping(address => uint256)) public playerIndex;
    mapping(uint256 => address[]) public winners;
    mapping(uint256 => bool) public houseCutBurned;

    // Portfolio snapshots: leagueId => wallet => starting value in USDC (18 decimals)
    mapping(uint256 => mapping(address => uint256)) public startingValue;

    event LeagueCreated(uint256 indexed leagueId, address indexed creator, uint256 entryFee, uint256 duration);
    event PlayerJoined(uint256 indexed leagueId, address indexed player);
    event LeagueStarted(uint256 indexed leagueId, uint256 startTime, uint256 endTime);
    event LeagueSettled(uint256 indexed leagueId, address[] winners);
    event WinningsClaimed(uint256 indexed leagueId, address indexed winner, uint256 amount);
    event LeagueCancelled(uint256 indexed leagueId);
    event RefundClaimed(uint256 indexed leagueId, address indexed player, uint256 amount);
    event TokenAdded(uint256 indexed index, address token, address pair);
    event TokenRemoved(uint256 indexed index);

    constructor(address _clawd) Ownable(msg.sender) {
        clawd = IERC20(_clawd);
        usdcDecimals = 6;
    }

    // ─── Token Registry Management ───

    /// @notice Set the ETH/USDC pair used to price native ETH and ETH-paired tokens
    function setEthUsdcPair(address _pair, bool _ethIsToken0) external onlyOwner {
        ethUsdcPair = _pair;
        ethIsToken0InPair = _ethIsToken0;
    }

    /// @notice Add a token to the registry
    /// @param token ERC-20 address (use address(0) for native ETH — but ETH is always included automatically)
    /// @param pair V2-style pair address
    /// @param isToken0 Whether this token is token0 in the pair
    /// @param decimals Token decimals
    /// @param pairedWithETH True if pair is token/WETH, false if token/USDC
    function addToken(
        address token,
        address pair,
        bool isToken0,
        uint8 decimals,
        bool pairedWithETH
    ) external onlyOwner {
        tokenRegistry.push(TokenInfo({
            token: token,
            pair: pair,
            isToken0: isToken0,
            decimals: decimals,
            pairedWithETH: pairedWithETH
        }));
        emit TokenAdded(tokenRegistry.length - 1, token, pair);
    }

    /// @notice Remove last token from registry (swap-and-pop for gas efficiency)
    function removeToken(uint256 index) external onlyOwner {
        require(index < tokenRegistry.length, "Index out of bounds");
        tokenRegistry[index] = tokenRegistry[tokenRegistry.length - 1];
        tokenRegistry.pop();
        emit TokenRemoved(index);
    }

    function getTokenRegistryLength() external view returns (uint256) {
        return tokenRegistry.length;
    }

    // ─── Portfolio Valuation ───

    /// @notice Get the price of a token in USDC terms (returned as 18-decimal fixed point)
    /// @dev Reads reserves from V2-style pair and computes price
    function _getTokenPriceInUSDC(TokenInfo storage info) internal view returns (uint256) {
        if (info.pair == address(0)) return 0;

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(info.pair).getReserves();
        if (reserve0 == 0 || reserve1 == 0) return 0;

        uint256 tokenReserve;
        uint256 quoteReserve;
        uint8 quoteDecimals;

        if (info.isToken0) {
            tokenReserve = uint256(reserve0);
            quoteReserve = uint256(reserve1);
        } else {
            tokenReserve = uint256(reserve1);
            quoteReserve = uint256(reserve0);
        }

        if (info.pairedWithETH) {
            // Price = (quoteReserve / tokenReserve) * ethPriceInUSDC
            // First get token price in ETH (18 decimal fixed point)
            // tokenPriceInETH = quoteReserve * 1e18 / tokenReserve (adjusted for decimals)
            uint256 tokenPriceInETH = (quoteReserve * (10 ** info.decimals) * 1e18) / (tokenReserve * 1e18);
            uint256 ethPrice = _getETHPriceInUSDC();
            return (tokenPriceInETH * ethPrice) / 1e18;
        } else {
            // Paired with USDC directly
            // price = quoteReserve * 10^tokenDecimals * 1e18 / (tokenReserve * 10^usdcDecimals)
            quoteDecimals = usdcDecimals;
            return (quoteReserve * (10 ** info.decimals) * 1e18) / (tokenReserve * (10 ** quoteDecimals));
        }
    }

    /// @notice Get ETH price in USDC (18-decimal fixed point)
    function _getETHPriceInUSDC() internal view returns (uint256) {
        if (ethUsdcPair == address(0)) return 0;

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(ethUsdcPair).getReserves();
        if (reserve0 == 0 || reserve1 == 0) return 0;

        uint256 ethReserve;
        uint256 usdcReserve;

        if (ethIsToken0InPair) {
            ethReserve = uint256(reserve0);
            usdcReserve = uint256(reserve1);
        } else {
            ethReserve = uint256(reserve1);
            usdcReserve = uint256(reserve0);
        }

        // ethPrice = usdcReserve * 1e18 * 1e18 / (ethReserve * 10^usdcDecimals)
        // Returns 18-decimal fixed point (e.g., 3000e18 = $3000)
        return (usdcReserve * 1e18 * 1e12) / ethReserve; // 1e12 = 1e18 / 10^6(usdc decimals)
    }

    /// @notice Get known portfolio value for a wallet in USDC (18-decimal fixed point)
    /// @dev Sums native ETH + all registered ERC-20 token values
    function getPortfolioValue(address wallet) public view returns (uint256 totalUSDC) {
        // 1. Native ETH value
        uint256 ethPrice = _getETHPriceInUSDC();
        totalUSDC = (wallet.balance * ethPrice) / 1e18;

        // 2. All registered tokens
        for (uint256 i = 0; i < tokenRegistry.length; i++) {
            TokenInfo storage info = tokenRegistry[i];
            if (info.token == address(0)) continue; // skip if somehow zero

            uint256 balance = IERC20(info.token).balanceOf(wallet);
            if (balance == 0) continue;

            uint256 price = _getTokenPriceInUSDC(info);
            // value = balance * price / 10^decimals
            totalUSDC += (balance * price) / (10 ** info.decimals);
        }
    }

    // ─── League Functions ───

    function createLeague(
        uint256 entryFee,
        uint256 duration,
        uint256 maxPlayers,
        uint256 maxPicks,
        uint256 houseCutBps,
        address[] calldata picks
    ) external nonReentrant {
        require(entryFee > 0, "Entry fee must be > 0");
        require(duration == 86400 || duration == 604800, "Duration must be 1 or 7 days");
        require(maxPlayers >= 2 && maxPlayers <= 10, "Max players 2-10");
        require(maxPicks >= 1 && maxPicks <= 3, "Max picks 1-3");
        require(houseCutBps <= 1000, "House cut max 10%");
        require(picks.length >= 1 && picks.length <= maxPicks, "Invalid picks count");
        _validatePicks(picks);

        uint256 leagueId = leagueCount++;

        _leagues[leagueId] = League({
            creator: msg.sender,
            entryFee: entryFee,
            duration: duration,
            maxPlayers: maxPlayers,
            maxPicks: maxPicks,
            startTime: 0,
            endTime: 0,
            totalPot: entryFee,
            houseCutBps: houseCutBps,
            status: LeagueStatus.Created,
            settledAt: 0,
            createdAt: block.timestamp
        });

        entries[leagueId].push(Entry({ player: msg.sender, picks: picks, claimed: false }));
        playerIndex[leagueId][msg.sender] = 1;

        clawd.safeTransferFrom(msg.sender, address(this), entryFee);

        emit LeagueCreated(leagueId, msg.sender, entryFee, duration);
        emit PlayerJoined(leagueId, msg.sender);

        if (entries[leagueId].length == maxPlayers) {
            _startLeague(leagueId);
        }
    }

    function joinLeague(uint256 leagueId, address[] calldata picks) external nonReentrant {
        League storage league = _leagues[leagueId];
        require(league.status == LeagueStatus.Created, "League not in Created status");
        require(entries[leagueId].length < league.maxPlayers, "League is full");
        require(playerIndex[leagueId][msg.sender] == 0, "Already joined");
        require(picks.length >= 1 && picks.length <= league.maxPicks, "Invalid picks count");
        _validatePicks(picks);

        entries[leagueId].push(Entry({ player: msg.sender, picks: picks, claimed: false }));
        playerIndex[leagueId][msg.sender] = entries[leagueId].length;

        league.totalPot += league.entryFee;

        clawd.safeTransferFrom(msg.sender, address(this), league.entryFee);

        emit PlayerJoined(leagueId, msg.sender);

        if (entries[leagueId].length == league.maxPlayers) {
            _startLeague(leagueId);
        }
    }

    function startLeague(uint256 leagueId) external {
        League storage league = _leagues[leagueId];
        require(msg.sender == league.creator, "Only creator");
        require(league.status == LeagueStatus.Created, "Not in Created status");
        require(entries[leagueId].length >= 2, "Need >= 2 players");
        _startLeague(leagueId);
    }

    /// @notice Settle a league. Anyone can call after the timer ends.
    ///         Reads current portfolio values, compares to snapshots, best % gain wins.
    function settleLeague(uint256 leagueId) external {
        League storage league = _leagues[leagueId];
        require(league.status == LeagueStatus.Active, "Not active");
        require(block.timestamp >= league.endTime, "League not ended");

        Entry[] storage leagueEntries = entries[leagueId];
        uint256 numEntries = leagueEntries.length;

        int256 bestScore = type(int256).min;

        // Calculate score for each player
        int256[] memory scores = new int256[](numEntries);
        for (uint256 i = 0; i < numEntries; i++) {
            address[] storage picks = leagueEntries[i].picks;
            int256 totalScore = 0;

            for (uint256 j = 0; j < picks.length; j++) {
                address pick = picks[j];
                uint256 startVal = startingValue[leagueId][pick];
                uint256 endVal = getPortfolioValue(pick);

                if (startVal > 0) {
                    // % change in basis points
                    totalScore += (int256(endVal) - int256(startVal)) * 10000 / int256(startVal);
                } else if (endVal > 0) {
                    totalScore += 10000; // 0 → something = +100%
                }
            }

            // Average across picks
            scores[i] = totalScore / int256(picks.length);

            if (scores[i] > bestScore) {
                bestScore = scores[i];
            }
        }

        // Collect all players with the best score
        for (uint256 i = 0; i < numEntries; i++) {
            if (scores[i] == bestScore) {
                winners[leagueId].push(leagueEntries[i].player);
            }
        }

        league.status = LeagueStatus.Settled;
        league.settledAt = block.timestamp;

        emit LeagueSettled(leagueId, winners[leagueId]);
    }

    function claimWinnings(uint256 leagueId) external nonReentrant {
        League storage league = _leagues[leagueId];
        require(league.status == LeagueStatus.Settled, "Not settled");

        uint256 idx = playerIndex[leagueId][msg.sender];
        require(idx != 0, "Not a player");
        Entry storage entry = entries[leagueId][idx - 1];
        require(!entry.claimed, "Already claimed");

        bool isWinner = false;
        address[] storage w = winners[leagueId];
        for (uint256 i = 0; i < w.length; i++) {
            if (w[i] == msg.sender) {
                isWinner = true;
                break;
            }
        }
        require(isWinner, "Not a winner");

        entry.claimed = true;

        uint256 houseCut = (league.totalPot * league.houseCutBps) / 10000;
        uint256 netPot = league.totalPot - houseCut;
        uint256 share = netPot / w.length;

        if (houseCut > 0 && !houseCutBurned[leagueId]) {
            houseCutBurned[leagueId] = true;
            clawd.safeTransfer(address(0xdead), houseCut);
        }

        clawd.safeTransfer(msg.sender, share);

        emit WinningsClaimed(leagueId, msg.sender, share);
    }

    function cancelLeague(uint256 leagueId) external {
        League storage league = _leagues[leagueId];

        if (league.status == LeagueStatus.Active) {
            require(block.timestamp > league.endTime + 24 hours, "Too early to cancel");
        } else if (league.status == LeagueStatus.Created) {
            require(block.timestamp > league.createdAt + 7 days, "Too early to cancel");
        } else {
            revert("Cannot cancel");
        }

        league.status = LeagueStatus.Cancelled;
        emit LeagueCancelled(leagueId);
    }

    function claimRefund(uint256 leagueId) external nonReentrant {
        League storage league = _leagues[leagueId];
        require(league.status == LeagueStatus.Cancelled, "Not cancelled");

        uint256 idx = playerIndex[leagueId][msg.sender];
        require(idx != 0, "Not a player");
        Entry storage entry = entries[leagueId][idx - 1];
        require(!entry.claimed, "Already refunded");

        entry.claimed = true;

        clawd.safeTransfer(msg.sender, league.entryFee);

        emit RefundClaimed(leagueId, msg.sender, league.entryFee);
    }

    // ─── View Functions ───

    function leagues(uint256 leagueId) external view returns (League memory) {
        return _leagues[leagueId];
    }

    function getEntries(uint256 leagueId) external view returns (Entry[] memory) {
        return entries[leagueId];
    }

    function getWinners(uint256 leagueId) external view returns (address[] memory) {
        return winners[leagueId];
    }

    /// @notice Get current score for a player's picks (basis points, can be negative)
    function getPlayerScore(uint256 leagueId, address player) external view returns (int256) {
        uint256 idx = playerIndex[leagueId][player];
        require(idx != 0, "Not a player");
        Entry storage entry = entries[leagueId][idx - 1];

        int256 totalScore = 0;
        for (uint256 j = 0; j < entry.picks.length; j++) {
            address pick = entry.picks[j];
            uint256 startVal = startingValue[leagueId][pick];
            uint256 endVal = getPortfolioValue(pick);

            if (startVal > 0) {
                totalScore += (int256(endVal) - int256(startVal)) * 10000 / int256(startVal);
            } else if (endVal > 0) {
                totalScore += 10000;
            }
        }

        return totalScore / int256(entry.picks.length);
    }

    /// @notice Get the ETH price in USDC (18-decimal fixed point) — useful for frontend
    function getETHPrice() external view returns (uint256) {
        return _getETHPriceInUSDC();
    }

    // ─── Internal ───

    function _startLeague(uint256 leagueId) internal {
        League storage league = _leagues[leagueId];
        league.status = LeagueStatus.Active;
        league.startTime = block.timestamp;
        league.endTime = block.timestamp + league.duration;

        // Snapshot portfolio values for all picks
        Entry[] storage leagueEntries = entries[leagueId];
        for (uint256 i = 0; i < leagueEntries.length; i++) {
            address[] storage picks = leagueEntries[i].picks;
            for (uint256 j = 0; j < picks.length; j++) {
                address pick = picks[j];
                if (startingValue[leagueId][pick] == 0) {
                    startingValue[leagueId][pick] = getPortfolioValue(pick);
                }
            }
        }

        emit LeagueStarted(leagueId, league.startTime, league.endTime);
    }

    function _validatePicks(address[] calldata picks) internal pure {
        for (uint256 i = 0; i < picks.length; i++) {
            require(picks[i] != address(0), "Zero address pick");
            for (uint256 j = i + 1; j < picks.length; j++) {
                require(picks[i] != picks[j], "Duplicate pick");
            }
        }
    }
}
