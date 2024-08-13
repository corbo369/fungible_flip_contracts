// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IBlast.sol";
import "./IBlastPoints.sol";
import "entropy-sdk-solidity/IEntropy.sol";
import "openzeppelin-contracts/access/Ownable.sol";

/**
 *  _______  __    __  .__   __.   _______  __  .______    __       _______     _______  __       __  .______
 * |   ____||  |  |  | |  \ |  |  /  _____||  | |   _  \  |  |     |   ____|   |   ____||  |     |  | |   _  \
 * |  |__   |  |  |  | |   \|  | |  |  __  |  | |  |_)  | |  |     |  |__      |  |__   |  |     |  | |  |_)  |
 * |   __|  |  |  |  | |  . `  | |  | |_ | |  | |   _  <  |  |     |   __|     |   __|  |  |     |  | |   ___/
 * |  |     |  `--'  | |  |\   | |  |__| | |  | |  |_)  | |  `----.|  |____    |  |     |  `----.|  | |  |
 * |__|      \______/  |__| \__|  \______| |__| |______/  |_______||_______|   |__|     |_______||__| | _|
 *
 *
 * @dev Coin flip game, built on Blast, where you double up or get rugged. Powered by Pyth Entropy,
 * our protocol is fast and efficient, and we take no house rake or fee, providing true 50/50 odds.
 *
 * Website: https://fungibleflip.io
 * Twitter: https://twitter.com/FungibleFlip
 *
 * @author corbo.eth
 */
contract FungibleFlip is Ownable {

    IBlast private blast;

    IEntropy private entropy;

    struct Stats {
        uint32 lastTen;
        uint32 numWins;
        uint32 numLosses;
        uint32 numHeads;
        uint32 numTails;
        uint8 streak;
    }

    struct FlipRequest {
        uint64 sequenceNumber;
        uint256 flipAmount;
        bytes32 randomNumber;
        address requester;
        bool choice;
    }

    // @dev Ether values of allowed wager sizes.
    uint256[6] public amounts;

    // @dev Minimum contract balance.
    uint256 public threshold;

    // @dev Used to build leaderboard.
    address[] public levelOneOrHigher;

    // @dev Pyth Entropy provider address
    address public entropyProvider;

    // @dev (Account -> level)
    mapping(address => uint256) public level;

    // @dev (Account -> exp) (500 exp / level)
    mapping(address => uint256) public experience;

    // @dev Stores global and individual account statistics
    mapping(address => Stats) public stats;

    // @dev (Account -> sequence number) (used to fetch the vrf request)
    mapping(address => uint64) public sequenceNumbers;

    // @dev (Sequence number -> deposit data used for flip txn)
    mapping(uint256 => FlipRequest) public requests;

    event LevelUp(address indexed user, uint256 level);

    event Deposit(address indexed user, uint64 sequenceNumber);

    event Result(address indexed user, bool choice, bool result, uint256 amount);

    constructor(
        address _blast,
        address _entropy,
        address _provider,
        uint256 _threshold,
        uint256[6] memory _amounts
    ) Ownable(msg.sender) {
        blast = IBlast(_blast);
        blast.configureClaimableGas();
        blast.configureAutomaticYield();
        entropy = IEntropy(_entropy);
        entropyProvider = _provider;
        threshold = _threshold;
        amounts = _amounts;
    }

    /**
     * @dev Records and stores user and global statistics after a successful flip. Heads/tails
     * choice count, win/loss count, last ten flips, and current streak are all recorded.
     */
    function recordStatistics(address _user, bool _choice, bool _win) internal {
        address global = address(this);

        stats[global].lastTen = (stats[global].lastTen << 2) & 0xFFFFF;
        stats[global].lastTen |= uint32(_choice ? 1 : 0) << 1 | (_win ? 1 : 0);

        stats[_user].lastTen = (stats[_user].lastTen << 2) & 0xFFFFF;
        stats[_user].lastTen |= uint32(_choice ? 1 : 0) << 1 | (_win ? 1 : 0);

        bool winStreak = stats[_user].streak >> 7 == 1;
        uint8 streakLength = stats[_user].streak & 0x7F;

        if (_choice) {
            stats[global].numHeads++;
            stats[_user].numHeads++;
        } else {
            stats[global].numTails++;
            stats[_user].numTails++;
        }

        if (_win) {
            stats[global].numWins++;
            stats[_user].numWins++;

            if (winStreak) streakLength++;
            else streakLength = 1;

            stats[_user].streak = (1 << 7) | streakLength;
        } else {
            stats[global].numLosses++;
            stats[_user].numLosses++;

            if (!winStreak) streakLength++;
            else streakLength = 1;

            stats[_user].streak = streakLength;
        }
    }

    /**
     * @dev Increases an accounts experience after a flip is completed, if their experience reaches
     * 500, their level is incremented and their experience is reset to 0. When an account reaches
     * level 1, their address is pushed to the array ('levelOneOrHigher').
     */
    function increaseExperience(address _requester, uint256 _flipAmount, bool _flipResult) internal {
        if (_flipResult) experience[_requester] += 10;
        experience[_requester] += _flipAmount / 1000000000000000;

        if (experience[_requester] >= 500) {
            if(level[_requester] == 0) levelOneOrHigher.push(_requester);
            level[_requester] += 1;
            experience[_requester] -= 500;
            emit LevelUp(_requester, level[_requester]);
        }
    }

    /**
     * @dev First txn in the flip process, ('userRandom') is a random bytes32 generated by the frontend,
     * and ('userCommitment') is the hashed version. These parameters are used to obtain the sequence number
     * from Entropy, and request a random number to determine the outcome of the coin flip.
     */
    function deposit(bytes32 userRandom, bytes32 userCommitment, bool choice) external payable {
        require(
            sequenceNumbers[msg.sender] == 0,
            "accounts must flip after a deposit"
        );
        require(
            address(this).balance >= threshold,
            "flipping is currently paused"
        );
        require(
            msg.value == amounts[0] ||
            msg.value == amounts[1] ||
            msg.value == amounts[2] ||
            msg.value == amounts[3] ||
            msg.value == amounts[4] ||
            msg.value == amounts[5],
            "invalid flip amount"
        );

        uint64 sequence = entropy.request{value: entropy.getFee(entropyProvider)}(
            entropyProvider,
            userCommitment,
            true
        );

        requests[sequence] = FlipRequest({
            sequenceNumber: sequence,
            flipAmount: msg.value,
            randomNumber: userRandom,
            requester: msg.sender,
            choice: choice
        });

        sequenceNumbers[msg.sender] = sequence;

        emit Deposit(msg.sender, sequence);
    }

    /**
     * @dev Second txn in the flip process, throws if caller is not the account linked to ('sequenceNumber').
     * This function completes the Entropy process, revealing the random number and settling the coin flip.
     */
    function flip(uint64 sequenceNumber, bytes32 providerRandom) external {
        require(
            requests[sequenceNumber].requester == msg.sender,
            "unauthorized requester"
        );

        bytes32 randomNumber = entropy.reveal(
            entropyProvider,
            sequenceNumber,
            requests[sequenceNumbers[msg.sender]].randomNumber,
            providerRandom
        );

        uint256 amount = requests[sequenceNumber].flipAmount;
        address requester = requests[sequenceNumber].requester;
        bool choice = requests[sequenceNumber].choice;
        bool result = uint256(randomNumber) % 2 == 0;
        bool win = choice == result;

        emit Result(requester, choice, result, amount);

        delete sequenceNumbers[requester];
        delete requests[sequenceNumber];

        recordStatistics(msg.sender, choice, win);
        increaseExperience(requester, amount, win);

        if (win) {
            (bool success, ) = payable(requester).call{value: 2 * amount}("");
            require(success, "transfer failed");
        }
    }

    // Owner functions
    function manualReset(address user) public onlyOwner {
        (bool success, ) = payable(user).call{value: (requests[sequenceNumbers[user]].flipAmount)}("");
        require(success, "transfer failed");
        delete requests[sequenceNumbers[user]];
        delete sequenceNumbers[user];
    }

    function setEntropy(address _entropy, address _provider) public onlyOwner {
        entropy = IEntropy(_entropy);
        entropyProvider = _provider;
    }

    function setPointsOperator(address _blastPoints, address _pointsOperator) public onlyOwner {
        IBlastPoints(_blastPoints).configurePointsOperator(_pointsOperator);
    }

    function setFlipAmounts(uint256[6] memory _amounts) public onlyOwner {
        amounts = _amounts;
    }

    function setThreshold(uint256 _threshold) public onlyOwner {
        threshold = _threshold;
    }

    function withdraw() public payable onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "transfer failed");
    }

    function claimGas() public onlyOwner {
        blast.claimMaxGas(address(this), owner());
    }

    receive() external payable {}
}
