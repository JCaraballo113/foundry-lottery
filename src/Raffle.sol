// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title A sample Raffle contract
 * @author John Caraballo
 * @notice This contract is a simple implementation of a raffle system
 * @dev Implements chainlink VRFv2.5 for random number generation
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors */
    error Raffle__NotEnoughEthEntered(
        uint256 amountEntered,
        uint256 requiredBalance
    );
    error Raffle__NotEnoughTimePassed(
        uint256 currentTime,
        uint256 lastTimeStamp,
        uint256 interval
    );
    error Raffle__NoPlayersInRaffle();
    error Raffle__TransferFailed();
    error Raffle__NotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );

    /* Type Declarations */
    /**
     * @notice Enum to represent the state of the raffle
     * @dev This is used to track whether the raffle is open or calculating a winner
     */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1; // Number of random words to request
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /** Events */
    event RaffleEntered(address indexed player, uint256 amount);
    event WinnerPicked(address indexed winner);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    /**
     * @notice Modifier to ensure that enough time has passed since the last draw
     * @dev This is used to enforce the interval between raffle draws
     */
    modifier onlyAfterInterval() {
        if ((block.timestamp - s_lastTimeStamp) < i_interval) {
            revert Raffle__NotEnoughTimePassed({
                currentTime: block.timestamp,
                lastTimeStamp: s_lastTimeStamp,
                interval: i_interval
            });
        }
        _;
    }

    /**
     * @notice Modifier to ensure that there are players in the raffle
     * @dev This is used to prevent actions when there are no players
     */
    modifier onlyIfPlayers() {
        if (s_players.length == 0) {
            revert Raffle__NoPlayersInRaffle();
        }
        _;
    }

    modifier onlyOpen() {
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__NotOpen();
        }
        _;
    }

    /**
     * @notice Allows users to enter the raffle by sending the required entrance fee
     * @dev The function is payable, meaning it can accept Ether
     */
    function enterRaffle() external payable onlyOpen {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthEntered({
                amountEntered: msg.value,
                requiredBalance: i_entranceFee
            });
        }
        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender, msg.value);
    }

    /**
     * @dev this is the function that Chainlink Keeper nodes call to check
     * if the lottery is ready to have a winner picked
     * The following should be true in order to return true:
     * 1. The time interval has passed between raffle runs
     * 2. The raffle is open
     * 3. The contract has ETH
     * Implicitly, your subscrption has LINK
     * @return upkeepNeeded - true if it's time to restart the lottery
     * @return ignored
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timePassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool contractHasETH = (address(this).balance > 0);
        bool hasPlayers = (s_players.length > 0);

        upkeepNeeded = (isOpen && hasPlayers && timePassed && contractHasETH);

        return (upkeepNeeded, bytes(""));
    }

    /**
     * @notice Picks a winner from the players in the raffle
     * @dev This function should implement the logic to select a winner
     */
    function performUpkeep(
        bytes calldata /* performData */
    ) external onlyIfPlayers {
        (bool upkeepNeeded, ) = checkUpkeep("");

        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded({
                currentBalance: address(this).balance,
                numPlayers: s_players.length,
                raffleState: uint256(s_raffleState)
            });
        }

        s_raffleState = RaffleState.CALCULATING;

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash, // Price you're willing to pay for randomness
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        s_vrfCoordinator.requestRandomWords(request);
    }

    function fulfillRandomWords(
        uint256 /* unused */,
        uint256[] calldata randomWords
    ) internal override {
        // Effects
        uint256 winnerIndex = randomWords[0] % s_players.length;
        address payable winner = s_players[winnerIndex];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0); // Reset players for the next raffle
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(winner);

        // Interactions
        (bool success, ) = winner.call{value: address(this).balance}("");

        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /** Getter Functions */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getPlayers() external view returns (address payable[] memory) {
        return s_players;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }
}
