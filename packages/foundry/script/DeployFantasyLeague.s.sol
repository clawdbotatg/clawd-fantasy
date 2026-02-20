// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import { FantasyLeague } from "../contracts/FantasyLeague.sol";
import { MockERC20 } from "../contracts/MockERC20.sol";

contract DeployFantasyLeague is ScaffoldETHDeploy {
    function run() external ScaffoldEthDeployerRunner {
        // Deploy mock CLAWD for local/testnet
        MockERC20 mockClawd = new MockERC20("CLAWD", "CLAWD");
        console.log("MockCLAWD deployed at:", address(mockClawd));

        // Deploy FantasyLeague with deployer as reporter
        FantasyLeague fantasyLeague = new FantasyLeague(address(mockClawd), deployer);
        console.log("FantasyLeague deployed at:", address(fantasyLeague));

        // Register deployments for SE2 frontend
        deployments.push(Deployment("MockCLAWD", address(mockClawd)));
        deployments.push(Deployment("FantasyLeague", address(fantasyLeague)));
    }
}
