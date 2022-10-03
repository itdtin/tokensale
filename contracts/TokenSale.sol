// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract TokenSale is Ownable {

  event Reserve(address indexed user, uint256 native, uint256 totalReserve);
  event TokensClaimed(address indexed user, uint256 amount);
  event Lock(uint amount, address user);

  mapping(address => uint256) public reserves;
  mapping(address => uint256) public claimed;
  mapping(address => uint256) public claimTime;

  uint256 private constant RATE_PRECISION = 1e18;
  uint256 public HARD_CAP;
  uint256 public MIN_RESERVE_SIZE;
  uint256 public MAX_RESERVE_SIZE; // Native
  uint256 public immutable TOKENS_PER_NATIVE;

  uint256 public VESTING_PERIOD_COUNTER;
  uint256 public VESTING_PERIOD;
  uint256 public LOCK_PERIOD;

  uint256 public totalReserve;
  IERC20 private token;
  uint256 public startTime;
  uint256 public finishTime;


  modifier isAddress(address to) {
    require(to != address(0), "Sale:: Zero Address");
    _;
  }

  modifier isStarted() {
    require(startTime != 0, "Sale:: Not started");
    _;
  }

  modifier notStarted() {
    require(startTime == 0, "Sale:: Started");
    _;
  }

  modifier claimAllowed() {
    require(finishTime != 0, "Sale:: Not finished");
    _;
  }

  constructor(
    IERC20 _token,
    uint256 _minReserve,
    uint256 _maxReserve,
    uint256 _tokensPerNative,
    uint256 _vestingPeriod,
    uint256 _vestingPeriodCounter,
    uint256 _lockPeriod
  ) {
    token = _token;
    MIN_RESERVE_SIZE = _minReserve;
    MAX_RESERVE_SIZE = _maxReserve;
    TOKENS_PER_NATIVE = _tokensPerNative;
    VESTING_PERIOD_COUNTER = _vestingPeriodCounter;
    VESTING_PERIOD = _vestingPeriod;
    LOCK_PERIOD = _lockPeriod;
  }

  // allows users to claim their tokens
  function finishSale() external isStarted onlyOwner {
    finishTime = block.timestamp;
  }

  function startSale() external notStarted onlyOwner {
    startTime = block.timestamp;
    HARD_CAP = token.balanceOf(address(this)) * RATE_PRECISION / TOKENS_PER_NATIVE;
  }

  function collectFunds(address to) external claimAllowed onlyOwner isAddress(to) {
    (bool success, ) = payable(to).call{value: address(this).balance}("");
    require(success, 'Transfer failed.');
  }

  receive() external payable {
    if(startTime == 0) revert("Sale:: not started");
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

  function tokensToClaim(address _beneficiary) external view returns(uint256) {
    (uint256 tokensAmount, ) = _tokensToClaim(_beneficiary);
    return tokensAmount;
  }

  /**
    @dev This function returns tokensAmount available to claim. Calculates it based on several vesting periods if applicable.
  */
  function _tokensToClaim(address _beneficiary) private view returns(uint256 tokensAmount, uint256 lastClaim) {
    uint256 tokensLeft = reserves[_beneficiary] * TOKENS_PER_NATIVE / RATE_PRECISION;
    if (tokensLeft == 0 || block.timestamp < LOCK_PERIOD + finishTime) {
      return (0, 0);
    }

    lastClaim = claimTime[_beneficiary];
    bool firstClaim;

    if (lastClaim == 0) { // first time claim, set it to a sale finish time
      firstClaim = true;
      unchecked{ lastClaim = finishTime + LOCK_PERIOD; }
    }

    if (lastClaim > block.timestamp) {
      // has not started yet
      return (0, 0);
    }

    uint256 tokensClaimed = claimed[_beneficiary];
    uint256 tokensPerPeriod = (tokensClaimed + tokensLeft) * VESTING_PERIOD_COUNTER / VESTING_PERIOD;
    uint256 periodsPassed = (block.timestamp - lastClaim) / VESTING_PERIOD_COUNTER;
    // align it to period passed
    lastClaim = lastClaim + periodsPassed * VESTING_PERIOD_COUNTER;

    if (firstClaim)  { // first time claim, add extra period
      unchecked {
        periodsPassed += 1;
      }
    }
    tokensAmount = periodsPassed * tokensPerPeriod;
    if (tokensAmount > tokensLeft){
      tokensAmount = tokensLeft;
    }
  }

  // claims vested tokens for a given beneficiary
  function claimFor(address _beneficiary) external claimAllowed {
    _processClaim(_beneficiary);
  }

  // convenience function for beneficiaries to call to claim all of their vested tokens
  function claimForSelf() external claimAllowed {
    _processClaim(msg.sender);
  }

  function claimForMany(address[] calldata _beneficiaries) external claimAllowed {
    uint256 length = _beneficiaries.length;
    for (uint256 i; i < length; ++i) {
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
    reserves[_beneficiary] = reserves[_beneficiary] - amountToClaim * RATE_PRECISION / TOKENS_PER_NATIVE;

    _sendTokens(_beneficiary, amountToClaim);

    emit TokensClaimed(_beneficiary, amountToClaim);
  }

  // send tokens to beneficiary and remove obligation
  function _sendTokens(address _beneficiary, uint256 _amountToSend) internal {
    token.transfer(_beneficiary, _amountToSend);
  }
}
