// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import { FantasyLeague } from "../contracts/FantasyLeague.sol";

contract DeployFantasyLeagueBase is ScaffoldETHDeploy {
    // Real CLAWD token on Base
    address constant CLAWD_TOKEN = 0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07;

    function run() external ScaffoldEthDeployerRunner {
        // Deploy FantasyLeague with real CLAWD and deployer as reporter
        FantasyLeague fantasyLeague = new FantasyLeague(CLAWD_TOKEN, deployer);
        console.log("FantasyLeague deployed at:", address(fantasyLeague));

        // Register deployment for SE2 frontend
        deployments.push(Deployment("FantasyLeague", address(fantasyLeague)));
    }
}
