pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenSale is Ownable {

  uint256 public constant MIN_RESERVE_SIZE = 0.5 * 1e18; // 0.5 ETH
  uint256 public constant MAX_RESERVE_SIZE = 2 * 1e18; // 2 ETH
  uint256 public constant TOKENS_PER_ETH = 1.42857 * 1e18;
  uint256 public constant VESTING_AMOUNT = 25; // 25 %
  uint256 public constant VESTING_AMOUNT_TOTAL = 100; // 100 %
  uint256 public constant VESTING_PERIOD = 30 days;
  uint256 public constant RATE_PRECISION = 1e18;

  event Reserve(address indexed user, uint256 busd, uint256 totalReserve);
  event TokensClaimed(address indexed user, uint256 amount);

  mapping(address => uint256) public claimed;
  mapping(address => uint256) public claimTime;
  mapping(address => uint256) public reserves;

  uint256 public totalReserve; // ETH
  IERC20 public token;
  uint256 public HARD_CAP; // ETH
  uint256 public startTime;
  uint256 public finishTime;

  modifier isStarted() {
    require(startTime != 0, "sale is not started");
    _;
  }

  modifier notStarted() {
    require(startTime == 0, "sale is started");
    _;
  }

  modifier claimAllowed() {
    require(finishTime != 0, "sale is not finished");
    _;
  }

  constructor(IERC20 _token, uint256 hardcap) public {
    token = _token;
    HARD_CAP = hardcap;
  }

  // allows users to claim their tokens
  function finishSale() external isStarted onlyOwner {
    finishTime = block.timestamp;
  }

  function startSale() external notStarted onlyOwner {
    startTime = block.timestamp;
  }

  function collectFunds(address payable to) external claimAllowed onlyOwner {
    (bool success, ) = to.call{value: address(this).balance}('');
    require(success, 'Transfer failed.');
  }

  receive() external payable {
    if(startTime == 0) {
      revert("Sale:: not started");
    }
    if(msg.value != 0) {

      uint256 nativeAmount = msg.value;
      // check hardcap
      uint256 newTotalReserves = totalReserve + nativeAmount;
      if (newTotalReserves > HARD_CAP) {
        revert("Sale:: hardcap reached");
      }

      uint256 currentReserve = reserves[msg.sender];
      uint256 newReserve;
    unchecked {
      newReserve = currentReserve + nativeAmount;
    }
      require(newReserve >= MIN_RESERVE_SIZE && newReserve <= MAX_RESERVE_SIZE, "Sale:: too much or too little");

      reserves[msg.sender] = newReserve;

      totalReserve = newTotalReserves;

      emit Reserve(msg.sender, nativeAmount, newTotalReserves);
    }
  }

  function tokensToClaim(address _beneficiary) public view returns(uint256) {
    (uint256 tokensAmount, ) = _tokensToClaim(_beneficiary);
    return tokensAmount;
  }

  /**
    @dev This function returns tokensAmount available to claim. Calculates it based on several vesting periods if applicable.
  */
  function _tokensToClaim(address _beneficiary) private view returns(uint256 tokensAmount, uint256 lastClaim) {
    uint256 tokensLeft = reserves[_beneficiary] * TOKENS_PER_ETH / RATE_PRECISION;
    if (tokensLeft == 0) {
      return (0, 0);
    }

    lastClaim = claimTime[_beneficiary];
    bool firstClaim = false;

    if (lastClaim == 0) { // first time claim, set it to a sale finish time
      firstClaim = true;
      lastClaim = finishTime;
    }

    if (lastClaim > block.timestamp) {
      // has not started yet
      return (0, 0);
    }

    uint256 tokensClaimed = claimed[_beneficiary];
    uint256 tokensPerPeriod = (tokensClaimed + tokensLeft) * VESTING_AMOUNT / VESTING_AMOUNT_TOTAL;
    uint256 periodsPassed = (block.timestamp - lastClaim) / VESTING_PERIOD;

    // align it to period passed
    lastClaim = lastClaim + (periodsPassed * VESTING_PERIOD);

    if (firstClaim)  { // first time claim, add extra period
      periodsPassed += 1;
    }

    tokensAmount = periodsPassed * tokensPerPeriod;
  }

  // claims vested tokens for a given beneficiary
  function claimFor(address _beneficiary) external claimAllowed {
    _processClaim(_beneficiary);
  }

  // convenience function for beneficiaries to call to claim all of their vested tokens
  function claimForSelf() external claimAllowed {
    _processClaim(msg.sender);
  }

  function claimForMany(address[] memory _beneficiaries) external claimAllowed {
    uint256 length = _beneficiaries.length;
    for (uint256 i = 0; i < length; i++) {
      _processClaim(_beneficiaries[i]);
    }
  }

  // Calculates the claimable tokens of a beneficiary and sends them.
  function _processClaim(address _beneficiary) internal {
    (uint256 amountToClaim, uint256 lastClaim) = _tokensToClaim(_beneficiary);

    if (amountToClaim == 0) {
      return;
    }
    claimTime[_beneficiary] = lastClaim;
    claimed[_beneficiary] = claimed[_beneficiary] + amountToClaim;
    reserves[_beneficiary] = reserves[_beneficiary] - (amountToClaim * RATE_PRECISION / TOKENS_PER_ETH);

    _sendTokens(_beneficiary, amountToClaim);

    emit TokensClaimed(_beneficiary, amountToClaim);
  }

  // send tokens to beneficiary and remove obligation
  function _sendTokens(address _beneficiary, uint256 _amountToSend) internal {
    SafeERC20.safeTransfer(IERC20(token), _beneficiary, _amountToSend);
  }
}
