// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FantasyLeague is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public clawd;
    address public reporter;
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
        uint256 resultSubmittedAt;
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
    // leagueId => player => hasDisputed
    mapping(uint256 => mapping(address => bool)) public hasDisputed;
    // leagueId => whether house cut has been burned
    mapping(uint256 => bool) public houseCutBurned;

    event LeagueCreated(uint256 indexed leagueId, address indexed creator, uint256 entryFee, uint256 duration);
    event PlayerJoined(uint256 indexed leagueId, address indexed player);
    event LeagueStarted(uint256 indexed leagueId, uint256 startTime, uint256 endTime);
    event ResultsReported(uint256 indexed leagueId, address[] winners);
    event ResultsDisputed(uint256 indexed leagueId, address indexed disputer);
    event WinningsClaimed(uint256 indexed leagueId, address indexed winner, uint256 amount);
    event LeagueCancelled(uint256 indexed leagueId);
    event RefundClaimed(uint256 indexed leagueId, address indexed player, uint256 amount);

    constructor(address _clawd, address _reporter) Ownable(msg.sender) {
        clawd = IERC20(_clawd);
        reporter = _reporter;
    }

    function setReporter(address _reporter) external onlyOwner {
        reporter = _reporter;
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
            resultSubmittedAt: 0,
            createdAt: block.timestamp
        });

        // Creator auto-joins
        entries[leagueId].push(Entry({ player: msg.sender, picks: picks, claimed: false }));
        playerIndex[leagueId][msg.sender] = 1; // index 0 + 1

        clawd.safeTransferFrom(msg.sender, address(this), entryFee);

        emit LeagueCreated(leagueId, msg.sender, entryFee, duration);
        emit PlayerJoined(leagueId, msg.sender);

        // Auto-start if full (maxPlayers == 1 not possible since min is 2, but check anyway)
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
        playerIndex[leagueId][msg.sender] = entries[leagueId].length; // 1-indexed

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

    function reportResults(uint256 leagueId, address[] calldata _winners) external {
        require(msg.sender == reporter, "Only reporter");
        League storage league = _leagues[leagueId];
        require(league.status == LeagueStatus.Active, "Not active");
        require(block.timestamp >= league.endTime, "League not ended");
        require(_winners.length >= 1, "Need >= 1 winner");

        // Validate winners are players
        for (uint256 i = 0; i < _winners.length; i++) {
            require(playerIndex[leagueId][_winners[i]] != 0, "Winner not a player");
        }

        league.status = LeagueStatus.Settled;
        league.resultSubmittedAt = block.timestamp;
        winners[leagueId] = _winners;

        emit ResultsReported(leagueId, _winners);
    }

    function disputeResults(uint256 leagueId) external {
        League storage league = _leagues[leagueId];
        require(league.status == LeagueStatus.Settled, "Not settled");
        require(playerIndex[leagueId][msg.sender] != 0, "Not a player");
        require(block.timestamp <= league.resultSubmittedAt + 1 hours, "Dispute window closed");
        require(!hasDisputed[leagueId][msg.sender], "Already disputed");

        hasDisputed[leagueId][msg.sender] = true;
        league.status = LeagueStatus.Active;
        delete winners[leagueId];

        emit ResultsDisputed(leagueId, msg.sender);
    }

    function claimWinnings(uint256 leagueId) external nonReentrant {
        League storage league = _leagues[leagueId];
        require(league.status == LeagueStatus.Settled, "Not settled");
        require(block.timestamp > league.resultSubmittedAt + 1 hours, "Dispute window open");

        uint256 idx = playerIndex[leagueId][msg.sender];
        require(idx != 0, "Not a player");
        Entry storage entry = entries[leagueId][idx - 1];
        require(!entry.claimed, "Already claimed");

        // Check caller is a winner
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

        // Burn house cut on first claim
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

    function leagues(uint256 leagueId) external view returns (League memory) {
        return _leagues[leagueId];
    }

    // View helpers
    function getEntries(uint256 leagueId) external view returns (Entry[] memory) {
        return entries[leagueId];
    }

    function getWinners(uint256 leagueId) external view returns (address[] memory) {
        return winners[leagueId];
    }

    function _startLeague(uint256 leagueId) internal {
        League storage league = _leagues[leagueId];
        league.status = LeagueStatus.Active;
        league.startTime = block.timestamp;
        league.endTime = block.timestamp + league.duration;
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
