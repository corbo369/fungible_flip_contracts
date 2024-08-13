// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IBlast.sol";
import "./IBlastPoints.sol";
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
 * @dev Coin flip game, built on Blast, where you double up or get rugged. Our protocol
 * implements blast's native features, to take no house rake, and provide true 50/50 odds.
 *
 * Website: https://fungibleflip.io
 * Twitter: https://twitter.com/FungibleFlip
 *
 * @author corbo.eth
 */
contract FungibleFlip is Ownable {

    IBlast private blast;

    struct Stats {
        uint32 lastTen;
        uint32 numWins;
        uint32 numLosses;
        uint32 numChoiceHeads;
        uint32 numChoiceTails;
        uint32 numResultHeads;
        uint32 numResultTails;
        uint8 streak;
    }

    struct FlipRequest {
        uint256 id;
        uint256 flipAmount;
        address requester;
        bool choice;
    }

    // @dev Current flip id.
    uint256 public flipId;

    // @dev Minimum contract balance.
    uint256 public threshold;

    // @dev Gas fee compensation for rng signer.
    uint256 public rngFee;

    // @dev Allowed wager sizes.
    uint256[6] public amounts;

    // @dev Used to build leaderboard.
    address[] public levelOneOrHigher;

    // @dev RNG signer address.
    address public rngSigner;

    // @dev (Account -> level)
    mapping(address => uint256) public level;

    // @dev (Account -> experience)
    mapping(address => uint256) public experience;

    // @dev (Account -> flipId)
    mapping(address => uint256) public userFlipId;

    // @dev (flipId -> data used for flip txn)
    mapping(uint256 => FlipRequest) public requests;

    // @dev (Account -> statistics)
    mapping(address => Stats) public stats;

    event LevelUp(address indexed user, uint256 level);

    event Deposit(address indexed user, uint256 flipId);

    event Result(address indexed user, bool choice, bool result, uint256 amount);

    constructor(
        address _blast,
        address _signer,
        uint256 _threshold,
        uint256 _rngFee,
        uint256[6] memory _amounts
    ) Ownable(msg.sender) {
        blast = IBlast(_blast);
        blast.configureClaimableGas();
        blast.configureAutomaticYield();
        IBlastPoints(0x2536FE9ab3F511540F2f9e2eC2A805005C3Dd800).configurePointsOperator(_signer);
        rngSigner = _signer;
        threshold = _threshold;
        rngFee = _rngFee;
        amounts = _amounts;
    }

    /**
     * @dev Records and stores user and global statistics after a successful flip. Heads/tails
     * choice/result count, win/loss count, last ten flips, and current streak are all recorded.
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
            stats[global].numChoiceHeads++;
            stats[_user].numChoiceHeads++;
            if(_win) {
                stats[global].numResultHeads++;
                stats[_user].numResultHeads++;
            } else {
                stats[global].numResultTails++;
                stats[_user].numResultTails++;
            }
        } else {
            stats[global].numChoiceTails++;
            stats[_user].numChoiceTails++;
            if(_win) {
                stats[global].numResultTails++;
                stats[_user].numResultTails++;
            } else {
                stats[global].numResultHeads++;
                stats[_user].numResultHeads++;
            }
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
    function increaseExperience(address _user, uint256 _flipAmount, bool _flipResult) internal {
        if (_flipResult) experience[_user] += 10;
        experience[_user] += _flipAmount / 1000000000000000;

        if (experience[_user] >= 500) {
            if(level[_user] == 0) levelOneOrHigher.push(_user);
            level[_user] += 1;
            experience[_user] -= 500;
            emit LevelUp(_user, level[_user]);
        }
    }

    /**
     * @dev First txn in the flip process, ('choice') is true for heads or false for tails.
     * Once called, this function sends a request to the ('vrfSigner') to settle the flip.
     */
    function deposit(bool choice) external payable {
        require(
            userFlipId[msg.sender] == 0,
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

        userFlipId[msg.sender] = flipId;

        requests[flipId] = FlipRequest({
            id: flipId,
            flipAmount: msg.value,
            requester: msg.sender,
            choice: choice
        });

        emit Deposit(msg.sender, flipId);

        flipId++;
    }

    /**
     * @dev Second txn in the flip process, throws if caller is not the vrf signer.
     * This function increases experience, records statistics, and settles the coin flip.
     */
    function flip(uint64 id, bytes32 randomBytes) external {
        require(msg.sender == rngSigner, "unauthorized requester");

        uint256 amount = requests[id].flipAmount;
        address user = requests[id].requester;
        bool choice = requests[id].choice;
        bool result = uint256(randomBytes) % 2 == 0;
        bool win = choice == result;

        emit Result(user, choice, result, amount);

        delete userFlipId[user];
        delete requests[id];

        recordStatistics(user, choice, win);
        increaseExperience(user, amount, win);

        if (win) {
            (bool successOne, ) = payable(user).call{value: 2 * amount - rngFee}("");
            (bool successTwo, ) = payable(rngSigner).call{value: rngFee}("");
            require(successOne && successTwo, "transfers failed");
        }
    }

    // Owner functions
    function setThreshold(uint256 _threshold) public onlyOwner {
        threshold = _threshold;
    }

    function setRngFee(uint256 _rngFee) public onlyOwner {
        rngFee = _rngFee;
    }

    function setFlipAmounts(uint256[6] memory _amounts) public onlyOwner {
        amounts = _amounts;
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
