// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/FantasyLeague.sol";
import "../contracts/MockERC20.sol";

contract FantasyLeagueTest is Test {
    FantasyLeague public fl;
    MockERC20 public token;

    address owner = address(this);
    address reporter = address(0xBEEF);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xC);
    address dave = address(0xD);

    uint256 constant ENTRY_FEE = 100e18;
    uint256 constant ONE_DAY = 86400;

    function setUp() public {
        token = new MockERC20("CLAWD", "CLAWD");
        fl = new FantasyLeague(address(token), reporter);

        address[4] memory users = [alice, bob, charlie, dave];
        for (uint256 i = 0; i < 4; i++) {
            token.mint(users[i], 10000e18);
            vm.prank(users[i]);
            token.approve(address(fl), type(uint256).max);
        }
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
        fl.createLeague(ENTRY_FEE, ONE_DAY, 2, 1, 500, _picks1(address(0x1)));
        return fl.leagueCount() - 1;
    }

    function _createAndFill() internal returns (uint256 id) {
        id = _createLeague2(alice);
        vm.prank(bob);
        fl.joinLeague(id, _picks1(address(0x2)));
    }

    function _settleWithWinners(uint256 id, address[] memory w) internal {
        vm.warp(_getEndTime(id));
        vm.prank(reporter);
        fl.reportResults(id, w);
    }

    // Tests
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
        fl.joinLeague(id, _picks1(address(0x2)));
        assertEq(token.balanceOf(bob), balBefore - ENTRY_FEE);
    }

    function test_AutoStartOnFull() public {
        uint256 id = _createAndFill();
        assertEq(uint256(_getStatus(id)), uint256(FantasyLeague.LeagueStatus.Active));
    }

    function test_ManualStart() public {
        vm.prank(alice);
        fl.createLeague(ENTRY_FEE, ONE_DAY, 3, 1, 500, _picks1(address(0x1)));
        uint256 id = fl.leagueCount() - 1;

        vm.prank(bob);
        fl.joinLeague(id, _picks1(address(0x2)));

        vm.prank(alice);
        fl.startLeague(id);
        assertEq(uint256(_getStatus(id)), uint256(FantasyLeague.LeagueStatus.Active));
    }

    function test_ReportResults() public {
        uint256 id = _createAndFill();
        address[] memory w = _picks1(alice);
        _settleWithWinners(id, w);
        assertEq(uint256(_getStatus(id)), uint256(FantasyLeague.LeagueStatus.Settled));
    }

    function test_DisputeResults() public {
        uint256 id = _createAndFill();
        _settleWithWinners(id, _picks1(alice));

        vm.prank(bob);
        fl.disputeResults(id);
        assertEq(uint256(_getStatus(id)), uint256(FantasyLeague.LeagueStatus.Active));
    }

    function test_ClaimWinnings() public {
        uint256 id = _createAndFill();
        _settleWithWinners(id, _picks1(alice));
        vm.warp(block.timestamp + 1 hours + 1);

        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        fl.claimWinnings(id);
        // totalPot=200e18, 5% cut=10e18, net=190e18
        assertEq(token.balanceOf(alice) - balBefore, 190e18);
    }

    function test_HouseCutBurned() public {
        uint256 id = _createAndFill();
        _settleWithWinners(id, _picks1(alice));
        vm.warp(block.timestamp + 1 hours + 1);

        vm.prank(alice);
        fl.claimWinnings(id);
        assertEq(token.balanceOf(address(0xdead)), 10e18);
    }

    function test_EvenSplitMultipleWinners() public {
        uint256 id = _createAndFill();
        address[] memory w = new address[](2);
        w[0] = alice;
        w[1] = bob;
        _settleWithWinners(id, w);
        vm.warp(block.timestamp + 1 hours + 1);

        uint256 balA = token.balanceOf(alice);
        uint256 balB = token.balanceOf(bob);

        vm.prank(alice);
        fl.claimWinnings(id);
        vm.prank(bob);
        fl.claimWinnings(id);

        assertEq(token.balanceOf(alice) - balA, 95e18);
        assertEq(token.balanceOf(bob) - balB, 95e18);
    }

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

    function test_RevertJoinFullLeague() public {
        uint256 id = _createAndFill();
        vm.prank(charlie);
        vm.expectRevert("League not in Created status");
        fl.joinLeague(id, _picks1(address(0x3)));
    }

    function test_RevertDoubleJoin() public {
        vm.prank(alice);
        fl.createLeague(ENTRY_FEE, ONE_DAY, 3, 1, 500, _picks1(address(0x1)));
        uint256 id = fl.leagueCount() - 1;

        vm.prank(alice);
        vm.expectRevert("Already joined");
        fl.joinLeague(id, _picks1(address(0x2)));
    }

    function test_RevertNonReporterReport() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        vm.prank(alice);
        vm.expectRevert("Only reporter");
        fl.reportResults(id, _picks1(alice));
    }

    function test_RevertClaimBeforeDisputeWindow() public {
        uint256 id = _createAndFill();
        _settleWithWinners(id, _picks1(alice));

        vm.prank(alice);
        vm.expectRevert("Dispute window open");
        fl.claimWinnings(id);
    }

    function test_RevertDoubleClaim() public {
        uint256 id = _createAndFill();
        _settleWithWinners(id, _picks1(alice));
        vm.warp(block.timestamp + 1 hours + 1);

        vm.prank(alice);
        fl.claimWinnings(id);

        vm.prank(alice);
        vm.expectRevert("Already claimed");
        fl.claimWinnings(id);
    }

    function testFuzz_EntryFee(uint256 fee) public {
        fee = bound(fee, 1, 1e30);
        token.mint(alice, fee);
        token.mint(bob, fee);
        vm.prank(alice);
        token.approve(address(fl), fee);
        vm.prank(bob);
        token.approve(address(fl), fee);

        vm.prank(alice);
        fl.createLeague(fee, ONE_DAY, 2, 1, 0, _picks1(address(0x1)));
        uint256 id = fl.leagueCount() - 1;

        vm.prank(bob);
        fl.joinLeague(id, _picks1(address(0x2)));

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
        fl.createLeague(fee, ONE_DAY, 2, 1, bps, _picks1(address(0x1)));
        uint256 id = fl.leagueCount() - 1;

        vm.prank(bob);
        fl.joinLeague(id, _picks1(address(0x2)));

        _settleWithWinners(id, _picks1(alice));
        vm.warp(block.timestamp + 1 hours + 1);

        uint256 totalPot = fee * 2;
        uint256 expectedCut = (totalPot * bps) / 10000;
        uint256 expectedWinnings = totalPot - expectedCut;

        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        fl.claimWinnings(id);

        assertEq(token.balanceOf(alice) - balBefore, expectedWinnings);
    }
}
