// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title FantasyLeague — Fully onchain fantasy crypto betting
/// @notice Pick wallet addresses you think will gain the most ETH. No oracles. No reporters.
///         Balances are snapshotted at league start and compared at settlement. Best % gain wins.
contract FantasyLeague is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public clawd;
    uint256 public leagueCount;

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

    // leagueId => League
    mapping(uint256 => League) internal _leagues;
    // leagueId => entries
    mapping(uint256 => Entry[]) public entries;
    // leagueId => player => entryIndex+1 (0 means not joined)
    mapping(uint256 => mapping(address => uint256)) public playerIndex;
    // leagueId => winners
    mapping(uint256 => address[]) public winners;
    // leagueId => whether house cut has been burned
    mapping(uint256 => bool) public houseCutBurned;

    // Onchain balance snapshots: leagueId => wallet pick => ETH balance at league start
    mapping(uint256 => mapping(address => uint256)) public startingBalance;

    event LeagueCreated(uint256 indexed leagueId, address indexed creator, uint256 entryFee, uint256 duration);
    event PlayerJoined(uint256 indexed leagueId, address indexed player);
    event LeagueStarted(uint256 indexed leagueId, uint256 startTime, uint256 endTime);
    event LeagueSettled(uint256 indexed leagueId, address[] winners);
    event WinningsClaimed(uint256 indexed leagueId, address indexed winner, uint256 amount);
    event LeagueCancelled(uint256 indexed leagueId);
    event RefundClaimed(uint256 indexed leagueId, address indexed player, uint256 amount);

    constructor(address _clawd) Ownable(msg.sender) {
        clawd = IERC20(_clawd);
    }

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

    /// @notice Settle a league. Anyone can call this after the league ends.
    ///         Reads current ETH balances of all picks, compares to starting snapshots,
    ///         and determines the winner(s) by best average % change.
    function settleLeague(uint256 leagueId) external {
        League storage league = _leagues[leagueId];
        require(league.status == LeagueStatus.Active, "Not active");
        require(block.timestamp >= league.endTime, "League not ended");

        Entry[] storage leagueEntries = entries[leagueId];
        uint256 numEntries = leagueEntries.length;

        // Calculate score for each player (in basis points, can be negative)
        int256 bestScore = type(int256).min;
        uint256 winnerCount = 0;

        // First pass: find the best score
        int256[] memory scores = new int256[](numEntries);
        for (uint256 i = 0; i < numEntries; i++) {
            address[] storage picks = leagueEntries[i].picks;
            int256 totalScore = 0;

            for (uint256 j = 0; j < picks.length; j++) {
                address pick = picks[j];
                uint256 startBal = startingBalance[leagueId][pick];
                uint256 endBal = pick.balance;

                if (startBal > 0) {
                    // % change in basis points: ((end - start) / start) * 10000
                    totalScore += (int256(endBal) - int256(startBal)) * 10000 / int256(startBal);
                } else if (endBal > 0) {
                    totalScore += 10000; // 0 → something = +100%
                }
                // 0 → 0 = 0 contribution
            }

            // Average across picks
            scores[i] = totalScore / int256(picks.length);

            if (scores[i] > bestScore) {
                bestScore = scores[i];
            }
        }

        // Second pass: collect all players with the best score (ties split the pot)
        for (uint256 i = 0; i < numEntries; i++) {
            if (scores[i] == bestScore) {
                winners[leagueId].push(leagueEntries[i].player);
                winnerCount++;
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

    // View functions
    function leagues(uint256 leagueId) external view returns (League memory) {
        return _leagues[leagueId];
    }

    function getEntries(uint256 leagueId) external view returns (Entry[] memory) {
        return entries[leagueId];
    }

    function getWinners(uint256 leagueId) external view returns (address[] memory) {
        return winners[leagueId];
    }

    /// @notice Get the current score for a player's picks (callable while league is active)
    function getPlayerScore(uint256 leagueId, address player) external view returns (int256) {
        uint256 idx = playerIndex[leagueId][player];
        require(idx != 0, "Not a player");
        Entry storage entry = entries[leagueId][idx - 1];

        int256 totalScore = 0;
        for (uint256 j = 0; j < entry.picks.length; j++) {
            address pick = entry.picks[j];
            uint256 startBal = startingBalance[leagueId][pick];
            uint256 endBal = pick.balance;

            if (startBal > 0) {
                totalScore += (int256(endBal) - int256(startBal)) * 10000 / int256(startBal);
            } else if (endBal > 0) {
                totalScore += 10000;
            }
        }

        return totalScore / int256(entry.picks.length);
    }

    // Internal functions
    function _startLeague(uint256 leagueId) internal {
        League storage league = _leagues[leagueId];
        league.status = LeagueStatus.Active;
        league.startTime = block.timestamp;
        league.endTime = block.timestamp + league.duration;

        // Snapshot starting ETH balances for all picks
        Entry[] storage leagueEntries = entries[leagueId];
        for (uint256 i = 0; i < leagueEntries.length; i++) {
            address[] storage picks = leagueEntries[i].picks;
            for (uint256 j = 0; j < picks.length; j++) {
                address pick = picks[j];
                if (startingBalance[leagueId][pick] == 0) {
                    startingBalance[leagueId][pick] = pick.balance;
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
