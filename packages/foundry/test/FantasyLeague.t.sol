// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/FantasyLeague.sol";
import "../contracts/MockERC20.sol";
import "../contracts/MockV2Pair.sol";

contract FantasyLeagueTest is Test {
    FantasyLeague public fl;
    MockERC20 public clawdToken;
    MockERC20 public weth;
    MockERC20 public usdc;
    MockERC20 public wbtc;
    MockV2Pair public ethUsdcPair;
    MockV2Pair public wbtcUsdcPair;

    address owner = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xC);

    // Wallets to pick
    address pick1 = address(0x1001);
    address pick2 = address(0x1002);

    uint256 constant ENTRY_FEE = 100e18;
    uint256 constant ONE_DAY = 86400;

    function setUp() public {
        clawdToken = new MockERC20("CLAWD", "CLAWD");
        weth = new MockERC20("WETH", "WETH");
        usdc = new MockERC20("USDC", "USDC");
        wbtc = new MockERC20("WBTC", "WBTC");

        fl = new FantasyLeague(address(clawdToken));

        // Set up ETH/USDC pair: 1 ETH = 3000 USDC
        // WETH (18 dec) / USDC (6 dec)
        // 1000 ETH : 3,000,000 USDC
        ethUsdcPair = new MockV2Pair(address(weth), address(usdc));
        ethUsdcPair.setReserves(1000e18, 3_000_000e6);
        fl.setEthUsdcPair(address(ethUsdcPair), true); // WETH is token0

        // WBTC/USDC pair: 1 WBTC = 60,000 USDC
        // WBTC (8 dec) / USDC (6 dec)
        // 100 WBTC : 6,000,000 USDC
        wbtcUsdcPair = new MockV2Pair(address(wbtc), address(usdc));
        wbtcUsdcPair.setReserves(100e8, 6_000_000e6);

        // Register WBTC in the token registry
        fl.addToken(
            address(wbtc),   // token
            address(wbtcUsdcPair), // pair
            true,            // wbtc is token0
            8,               // decimals
            false            // paired with USDC, not ETH
        );

        // Give players CLAWD tokens
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < 3; i++) {
            clawdToken.mint(users[i], 10000e18);
            vm.prank(users[i]);
            clawdToken.approve(address(fl), type(uint256).max);
        }

        // Give pick wallets some starting assets
        vm.deal(pick1, 10 ether);  // 10 ETH = $30,000
        vm.deal(pick2, 10 ether);  // 10 ETH = $30,000
        wbtc.mint(pick1, 1e8);     // 1 WBTC = $60,000 → pick1 total: $90,000
        wbtc.mint(pick2, 1e8);     // 1 WBTC = $60,000 → pick2 total: $90,000
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

    function _createAndFill() internal returns (uint256 id) {
        vm.prank(alice);
        fl.createLeague(ENTRY_FEE, ONE_DAY, 2, 1, 500, _picks1(pick1));
        id = fl.leagueCount() - 1;
        vm.prank(bob);
        fl.joinLeague(id, _picks1(pick2));
    }

    // ─── Portfolio Valuation Tests ───

    function test_GetPortfolioValue() public view {
        // pick1: 10 ETH ($30,000) + 1 WBTC ($60,000) = $90,000
        uint256 val = fl.getPortfolioValue(pick1);
        // Should be ~90000e18 (18-decimal USDC value)
        assertApproxEqRel(val, 90_000e18, 0.01e18); // within 1%
    }

    function test_GetETHPrice() public view {
        uint256 ethPrice = fl.getETHPrice();
        assertApproxEqRel(ethPrice, 3000e18, 0.01e18);
    }

    function test_PortfolioValueWithZeroBalance() public view {
        address empty = address(0x9999);
        uint256 val = fl.getPortfolioValue(empty);
        assertEq(val, 0);
    }

    // ─── Core League Tests ───

    function test_CreateLeague() public {
        vm.prank(alice);
        fl.createLeague(ENTRY_FEE, ONE_DAY, 2, 1, 500, _picks1(pick1));
        uint256 id = fl.leagueCount() - 1;
        FantasyLeague.League memory league = fl.leagues(id);
        assertEq(league.creator, alice);
        assertEq(league.entryFee, ENTRY_FEE);
    }

    function test_AutoStartOnFull() public {
        uint256 id = _createAndFill();
        assertEq(uint256(_getStatus(id)), uint256(FantasyLeague.LeagueStatus.Active));
    }

    function test_SnapshotsPortfolioValues() public {
        uint256 id = _createAndFill();
        uint256 startVal1 = fl.startingValue(id, pick1);
        uint256 startVal2 = fl.startingValue(id, pick2);
        // Both should have ~$90,000 snapshotted
        assertApproxEqRel(startVal1, 90_000e18, 0.01e18);
        assertApproxEqRel(startVal2, 90_000e18, 0.01e18);
    }

    // ─── Settlement with Portfolio Tracking ───

    function test_SettleLeague_Pick1GainsTokens() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        // pick1 buys 1 more WBTC: now has 2 WBTC ($120k) + 10 ETH ($30k) = $150k
        wbtc.mint(pick1, 1e8);

        fl.settleLeague(id);

        address[] memory w = fl.getWinners(id);
        assertEq(w.length, 1);
        assertEq(w[0], alice); // alice picked pick1
    }

    function test_SettleLeague_Pick2GainsETH() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        // pick2 gets 20 more ETH: now has 30 ETH ($90k) + 1 WBTC ($60k) = $150k
        vm.deal(pick2, 30 ether);

        fl.settleLeague(id);

        address[] memory w = fl.getWinners(id);
        assertEq(w.length, 1);
        assertEq(w[0], bob); // bob picked pick2
    }

    function test_SettleLeague_MixedChanges() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        // pick1: sells ETH, buys WBTC → 0 ETH + 2.5 WBTC = $150k (+67%)
        vm.deal(pick1, 0);
        wbtc.mint(pick1, 15e7); // +1.5 WBTC, total 2.5 WBTC

        // pick2: gains ETH but loses WBTC → 20 ETH ($60k) + 0 WBTC = $60k (-33%)
        vm.deal(pick2, 20 ether);
        // burn pick2's WBTC
        vm.prank(pick2);
        wbtc.transfer(address(0xdead), 1e8);

        fl.settleLeague(id);

        address[] memory w = fl.getWinners(id);
        assertEq(w.length, 1);
        assertEq(w[0], alice); // pick1 gained more
    }

    function test_SettleLeague_Tie() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        // Both wallets unchanged
        fl.settleLeague(id);

        address[] memory w = fl.getWinners(id);
        assertEq(w.length, 2); // tie, both win
    }

    function test_SettleLeague_PriceChange() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        // WBTC price doubles: 1 WBTC = $120,000
        // New reserves: 100 WBTC : 12,000,000 USDC
        wbtcUsdcPair.setReserves(100e8, 12_000_000e6);

        // pick1 still has 1 WBTC + 10 ETH = $120k + $30k = $150k (up from $90k)
        // pick2 same portfolio = same value = $150k
        // Both gained equally from price change → tie
        fl.settleLeague(id);

        address[] memory w = fl.getWinners(id);
        assertEq(w.length, 2); // tie
    }

    function test_SettleLeague_AnyoneCanCall() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        vm.deal(pick1, 20 ether); // pick1 gains

        vm.prank(charlie); // charlie is not a player
        fl.settleLeague(id);

        assertEq(uint256(_getStatus(id)), uint256(FantasyLeague.LeagueStatus.Settled));
    }

    function test_ClaimWinnings() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        vm.deal(pick1, 20 ether); // alice's pick wins
        fl.settleLeague(id);

        uint256 balBefore = clawdToken.balanceOf(alice);
        vm.prank(alice);
        fl.claimWinnings(id);
        assertEq(clawdToken.balanceOf(alice) - balBefore, 190e18); // 200 - 5% house
    }

    function test_HouseCutBurned() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        vm.deal(pick1, 20 ether);
        fl.settleLeague(id);

        vm.prank(alice);
        fl.claimWinnings(id);
        assertEq(clawdToken.balanceOf(address(0xdead)), 10e18);
    }

    function test_EvenSplitOnTie() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));

        fl.settleLeague(id); // tie

        vm.prank(alice);
        fl.claimWinnings(id);
        vm.prank(bob);
        fl.claimWinnings(id);

        // Each gets 95e18 (190/2)
    }

    function test_GetPlayerScore() public {
        uint256 id = _createAndFill();

        // pick1 gains: 10 ETH + 1 WBTC → 20 ETH + 1 WBTC
        // $90k → $120k = +33.3%
        vm.deal(pick1, 20 ether);

        int256 score = fl.getPlayerScore(id, alice);
        // ~3333 basis points (+33.3%)
        assertApproxEqAbs(score, 3333, 10);
    }

    // ─── Token Registry Tests ───

    function test_AddAndRemoveToken() public {
        uint256 lenBefore = fl.getTokenRegistryLength();
        fl.addToken(address(0x999), address(0x888), true, 18, false);
        assertEq(fl.getTokenRegistryLength(), lenBefore + 1);

        fl.removeToken(lenBefore);
        assertEq(fl.getTokenRegistryLength(), lenBefore);
    }

    // ─── Cancel & Refund ───

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

        uint256 balBefore = clawdToken.balanceOf(alice);
        vm.prank(alice);
        fl.claimRefund(id);
        assertEq(clawdToken.balanceOf(alice) - balBefore, ENTRY_FEE);
    }

    // ─── Reverts ───

    function test_RevertSettleBeforeEnd() public {
        uint256 id = _createAndFill();
        vm.expectRevert("League not ended");
        fl.settleLeague(id);
    }

    function test_RevertDoubleClaim() public {
        uint256 id = _createAndFill();
        vm.warp(_getEndTime(id));
        vm.deal(pick1, 20 ether);
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
        vm.deal(pick1, 20 ether); // alice wins
        fl.settleLeague(id);

        vm.prank(bob);
        vm.expectRevert("Not a winner");
        fl.claimWinnings(id);
    }

    // ─── Fuzz ───

    function testFuzz_EntryFee(uint256 fee) public {
        fee = bound(fee, 1, 1e30);
        clawdToken.mint(alice, fee);
        clawdToken.mint(bob, fee);
        vm.prank(alice);
        clawdToken.approve(address(fl), fee);
        vm.prank(bob);
        clawdToken.approve(address(fl), fee);

        vm.prank(alice);
        fl.createLeague(fee, ONE_DAY, 2, 1, 0, _picks1(pick1));
        uint256 id = fl.leagueCount() - 1;

        vm.prank(bob);
        fl.joinLeague(id, _picks1(pick2));

        assertEq(fl.leagues(id).totalPot, fee * 2);
    }
}
