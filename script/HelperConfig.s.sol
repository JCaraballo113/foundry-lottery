// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

abstract contract CodeConstants {
    /*VRF Mock Values*/
    uint96 public constant MOCK_BASE_FEE = 0.25 ether; // base fee for VRF
    uint96 public constant MOCK_GAS_PRICE_LINK = 1e9; // gas price for VRF
    int256 public constant MOCK_WEI_PER_UNIT_LINK = 4e15; // wei per unit link for VRF
    /* Chain IDs */
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is Script, CodeConstants {
    error HelperConfig__InvalidChainId(uint256 chainId);
    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint32 callbackGasLimit;
        uint256 subscriptionId;
        address link; // Optional, used for LINK token address
    }

    NetworkConfig public activeNetworkConfig;
    mapping(uint256 => NetworkConfig) public networkConfigs;

    constructor() {}

    function getConfigByChainId(
        uint256 chainId
    ) public returns (NetworkConfig memory) {
        NetworkConfig memory config = networkConfigs[chainId];
        if (config.vrfCoordinator != address(0)) {
            return config;
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId(chainId);
        }
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getSepoliaConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.01 ether,
                interval: 30,
                vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
                gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
                callbackGasLimit: 500000,
                subscriptionId: 32155733991699204436069338311532088664403636332731107975387361171790007973999,
                link: 0x779877A7B0D9E8603169DdbD7836e478b4624789
            });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.vrfCoordinator != address(0)) {
            return activeNetworkConfig;
        }

        // Deploy mocks and such
        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinator = new VRFCoordinatorV2_5Mock(
            MOCK_BASE_FEE, // base fee
            MOCK_GAS_PRICE_LINK, // gas price
            MOCK_WEI_PER_UNIT_LINK // wei per unit link
        );
        LinkToken linkToken = new LinkToken();
        vm.stopBroadcast();

        activeNetworkConfig = NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 30,
            vrfCoordinator: address(vrfCoordinator),
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            callbackGasLimit: 500000,
            subscriptionId: 0,
            link: address(linkToken) // Deploy a new LINK token for testing
        });

        return activeNetworkConfig;
    }
}
