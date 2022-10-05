// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.11;

interface IERC20 {
  /**
   * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
  event Transfer(address indexed from, address indexed to, uint256 value);

  /**
   * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
  event Approval(address indexed owner, address indexed spender, uint256 value);

  /**
   * @dev Returns the amount of tokens in existence.
     */
  function totalSupply() external view returns (uint256);

  /**
   * @dev Returns the amount of tokens owned by `account`.
     */
  function balanceOf(address account) external view returns (uint256);

  /**
   * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
  function transfer(address to, uint256 amount) external returns (bool);

  /**
   * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
  function allowance(address owner, address spender) external view returns (uint256);

  /**
   * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
  function approve(address spender, uint256 amount) external returns (bool);

  /**
   * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) external returns (bool);
}

abstract contract Context {
  function _msgSender() internal view virtual returns (address) {
    return msg.sender;
  }

  function _msgData() internal view virtual returns (bytes calldata) {
    return msg.data;
  }
}

abstract contract Ownable is Context {
  address private _owner;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  /**
   * @dev Initializes the contract setting the deployer as the initial owner.
     */
  constructor() {
    _transferOwnership(_msgSender());
  }

  /**
   * @dev Throws if called by any account other than the owner.
     */
  modifier onlyOwner() {
    _checkOwner();
    _;
  }

  /**
   * @dev Returns the address of the current owner.
     */
  function owner() public view virtual returns (address) {
    return _owner;
  }

  /**
   * @dev Throws if the sender is not the owner.
     */
  function _checkOwner() internal view virtual {
    require(owner() == _msgSender(), "Ownable: caller is not the owner");
  }

  /**
   * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
  function renounceOwnership() public virtual onlyOwner {
    _transferOwnership(address(0));
  }

  /**
   * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
  function transferOwnership(address newOwner) public virtual onlyOwner {
    require(newOwner != address(0), "Ownable: new owner is the zero address");
    _transferOwnership(newOwner);
  }

  /**
   * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
  function _transferOwnership(address newOwner) internal virtual {
    address oldOwner = _owner;
    _owner = newOwner;
    emit OwnershipTransferred(oldOwner, newOwner);
  }
}

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
