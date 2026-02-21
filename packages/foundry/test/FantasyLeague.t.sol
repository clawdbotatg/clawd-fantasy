// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/FantasyLeague.sol";
import "../contracts/MockERC20.sol";

contract FantasyLeagueTest is Test {
    FantasyLeague public fl;
    MockERC20 public token;

    address owner = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xC);
    address dave = address(0xD);

    // Wallets to pick (we'll manipulate their ETH balances)
    address pick1 = address(0x1001);
    address pick2 = address(0x1002);
    address pick3 = address(0x1003);

    uint256 constant ENTRY_FEE = 100e18;
    uint256 constant ONE_DAY = 86400;

    function setUp() public {
        token = new MockERC20("CLAWD", "CLAWD");
        fl = new FantasyLeague(address(token));

        address[4] memory users = [alice, bob, charlie, dave];
        for (uint256 i = 0; i < 4; i++) {
            token.mint(users[i], 10000e18);
            vm.prank(users[i]);
            token.approve(address(fl), type(uint256).max);
        }

        // Give pick wallets some starting ETH so we can manipulate them
        vm.deal(pick1, 10 ether);
        vm.deal(pick2, 10 ether);
        vm.deal(pick3, 10 ether);
    }

    // Helpers
    function _picks1(address a) internal pure returns (address[] memory p) {
        p = new address[](1);
        p[0] = a;
    }

    function _getEndTime(uint256 id) internal view returns (uint256) {
        return fl.leagues(id).endTime;
    }

    function _getStatus(uint256 id) internal view returns (FantasyLeague.LeagueStatus) {
        return fl.leagues(id).status;
    }

    function _getTotalPot(uint256 id) internal view returns (uint256) {
        return fl.leagues(id).totalPot;
    }

    function _createLeague2(address creator) internal returns (uint256) {
        vm.prank(creator);
        fl.createLeague(ENTRY_FEE, ONE_DAY, 2, 1, 500, _picks1(pick1));
        return fl.leagueCount() - 1;
    }

    function _createAndFill() internal returns (uint256 id) {
        id = _createLeague2(alice);
        vm.prank(bob);
        fl.joinLeague(id, _picks1(pick2));
    }

    // === Core Tests ===

    function test_CreateLeague() public {
        uint256 id = _createLeague2(alice);
        FantasyLeague.League memory league = fl.leagues(id);
        assertEq(league.creator, alice);
        assertEq(league.entryFee, ENTRY_FEE);
        assertEq(token.balanceOf(address(fl)), ENTRY_FEE);
    }

    function test_JoinLeague() public {
        uint256 id = _createLeague2(alice);
        uint256 balBefore = token.balanceOf(bob);
        vm.prank(bob);
        fl.joinLeague(id, _picks1(pick2));
        assertEq(token.balanceOf(bob), balBefore - ENTRY_FEE);
    }

    function test_AutoStartOnFull() public {
        uint256 id = _createAndFill();
        assertEq(uint256(_getStatus(id)), uint256(FantasyLeague.LeagueStatus.Active));
    }

    function test_ManualStart() public {
        vm.prank(alice);
        fl.createLeague(ENTRY_FEE, ONE_DAY, 3, 1, 500, _picks1(pick1));
        uint256 id = fl.leagueCount() - 1;

        vm.prank(bob);
        fl.joinLeague(id, _picks1(pick2));

        vm.prank(alice);
        fl.startLeague(id);
        assertEq(uint256(_getStatus(id)), uint256(FantasyLeague.LeagueStatus.Active));
    }

    function test_SnapshotsStartingBalances() public {
        uint256 id = _createAndFill();
        assertEq(fl.startingBalance(id, pick1), 10 ether);
        assertEq(fl.startingBalance(id, pick2), 10 ether);
    }

    // === Settlement Tests (the new onchain oracle) ===

    function test_SettleLeague_Pick1Gains() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        // pick1 gained 5 ETH, pick2 stayed the same
        vm.deal(pick1, 15 ether);

        fl.settleLeague(id);

        assertEq(uint256(_getStatus(id)), uint256(FantasyLeague.LeagueStatus.Settled));
        address[] memory w = fl.getWinners(id);
        assertEq(w.length, 1);
        assertEq(w[0], alice); // alice picked pick1
    }

    function test_SettleLeague_Pick2Gains() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        // pick2 gained more
        vm.deal(pick2, 20 ether);

        fl.settleLeague(id);

        address[] memory w = fl.getWinners(id);
        assertEq(w.length, 1);
        assertEq(w[0], bob); // bob picked pick2
    }

    function test_SettleLeague_Tie() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        // Both picks stay the same — tie
        fl.settleLeague(id);

        address[] memory w = fl.getWinners(id);
        assertEq(w.length, 2); // both win, split the pot
    }

    function test_SettleLeague_BothGainSamePercent() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        // Both gain 50%
        vm.deal(pick1, 15 ether);
        vm.deal(pick2, 15 ether);

        fl.settleLeague(id);

        address[] memory w = fl.getWinners(id);
        assertEq(w.length, 2); // tie
    }

    function test_SettleLeague_Pick1Loses() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        // pick1 lost ETH, pick2 gained
        vm.deal(pick1, 5 ether);
        vm.deal(pick2, 15 ether);

        fl.settleLeague(id);

        address[] memory w = fl.getWinners(id);
        assertEq(w.length, 1);
        assertEq(w[0], bob);
    }

    function test_SettleLeague_AnyoneCanCall() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        vm.deal(pick1, 15 ether);

        // charlie (not a player) can settle
        vm.prank(charlie);
        fl.settleLeague(id);

        assertEq(uint256(_getStatus(id)), uint256(FantasyLeague.LeagueStatus.Settled));
    }

    function test_ClaimWinnings() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        vm.deal(pick1, 15 ether); // alice's pick wins

        fl.settleLeague(id);

        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        fl.claimWinnings(id);
        // totalPot=200e18, 5% cut=10e18, net=190e18
        assertEq(token.balanceOf(alice) - balBefore, 190e18);
    }

    function test_HouseCutBurned() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        vm.deal(pick1, 15 ether);
        fl.settleLeague(id);

        vm.prank(alice);
        fl.claimWinnings(id);
        assertEq(token.balanceOf(address(0xdead)), 10e18);
    }

    function test_EvenSplitOnTie() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        // tie — both stay at 10 ETH
        fl.settleLeague(id);

        uint256 balA = token.balanceOf(alice);
        uint256 balB = token.balanceOf(bob);

        vm.prank(alice);
        fl.claimWinnings(id);
        vm.prank(bob);
        fl.claimWinnings(id);

        assertEq(token.balanceOf(alice) - balA, 95e18);
        assertEq(token.balanceOf(bob) - balB, 95e18);
    }

    function test_GetPlayerScore() public {
        uint256 id = _createAndFill();

        // pick1 goes from 10 to 15 ETH = +50% = +5000 bps
        vm.deal(pick1, 15 ether);

        int256 score = fl.getPlayerScore(id, alice);
        assertEq(score, 5000); // +50% in basis points
    }

    function test_GetPlayerScoreNegative() public {
        uint256 id = _createAndFill();

        // pick1 goes from 10 to 5 ETH = -50% = -5000 bps
        vm.deal(pick1, 5 ether);

        int256 score = fl.getPlayerScore(id, alice);
        assertEq(score, -5000);
    }

    // === Cancel & Refund ===

    function test_CancelStaleLeague() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id) + 24 hours + 1);
        fl.cancelLeague(id);
        assertEq(uint256(_getStatus(id)), uint256(FantasyLeague.LeagueStatus.Cancelled));
    }

    function test_RefundOnCancel() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id) + 24 hours + 1);
        fl.cancelLeague(id);

        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        fl.claimRefund(id);
        assertEq(token.balanceOf(alice) - balBefore, ENTRY_FEE);
    }

    // === Reverts ===

    function test_RevertJoinFullLeague() public {
        uint256 id = _createAndFill();
        vm.prank(charlie);
        vm.expectRevert("League not in Created status");
        fl.joinLeague(id, _picks1(pick3));
    }

    function test_RevertDoubleJoin() public {
        vm.prank(alice);
        fl.createLeague(ENTRY_FEE, ONE_DAY, 3, 1, 500, _picks1(pick1));
        uint256 id = fl.leagueCount() - 1;

        vm.prank(alice);
        vm.expectRevert("Already joined");
        fl.joinLeague(id, _picks1(pick2));
    }

    function test_RevertSettleBeforeEnd() public {
        uint256 id = _createAndFill();
        vm.expectRevert("League not ended");
        fl.settleLeague(id);
    }

    function test_RevertSettleNotActive() public {
        uint256 id = _createLeague2(alice);
        vm.expectRevert("Not active");
        fl.settleLeague(id);
    }

    function test_RevertDoubleClaim() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));
        vm.deal(pick1, 15 ether);
        fl.settleLeague(id);

        vm.prank(alice);
        fl.claimWinnings(id);

        vm.prank(alice);
        vm.expectRevert("Already claimed");
        fl.claimWinnings(id);
    }

    function test_RevertLoserClaim() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));
        vm.deal(pick1, 15 ether); // alice wins
        fl.settleLeague(id);

        vm.prank(bob);
        vm.expectRevert("Not a winner");
        fl.claimWinnings(id);
    }

    // === Fuzz Tests ===

    function testFuzz_EntryFee(uint256 fee) public {
        fee = bound(fee, 1, 1e30);
        token.mint(alice, fee);
        token.mint(bob, fee);
        vm.prank(alice);
        token.approve(address(fl), fee);
        vm.prank(bob);
        token.approve(address(fl), fee);

        vm.prank(alice);
        fl.createLeague(fee, ONE_DAY, 2, 1, 0, _picks1(pick1));
        uint256 id = fl.leagueCount() - 1;

        vm.prank(bob);
        fl.joinLeague(id, _picks1(pick2));

        assertEq(_getTotalPot(id), fee * 2);
    }

    function testFuzz_HouseCut(uint256 bps) public {
        bps = bound(bps, 0, 1000);
        uint256 fee = 1000e18;
        token.mint(alice, fee);
        token.mint(bob, fee);
        vm.prank(alice);
        token.approve(address(fl), fee);
        vm.prank(bob);
        token.approve(address(fl), fee);

        vm.prank(alice);
        fl.createLeague(fee, ONE_DAY, 2, 1, bps, _picks1(pick1));
        uint256 id = fl.leagueCount() - 1;

        vm.prank(bob);
        fl.joinLeague(id, _picks1(pick2));

        vm.warp(_getEndTime(id));
        vm.deal(pick1, 15 ether); // alice wins
        fl.settleLeague(id);

        uint256 totalPot = fee * 2;
        uint256 expectedCut = (totalPot * bps) / 10000;
        uint256 expectedWinnings = totalPot - expectedCut;

        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        fl.claimWinnings(id);

        assertEq(token.balanceOf(alice) - balBefore, expectedWinnings);
    }
}
