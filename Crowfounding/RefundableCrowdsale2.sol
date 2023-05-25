pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MyTokenCrowdsale is Crowdsale, TimedCrowdsale, RefundableCrowdsale, PostDeliveryCrowdsale, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Token being sold
    IERC20 private _token;

    // Amount of wei raised
    uint256 private _weiRaised;

    // Crowdsale goal
    uint256 private _goal;

    // Crowdsale rate
    uint256 private _rate;

    // Wallet to receive raised funds
    address private _wallet;

    // Crowdsale opening and closing times
    uint256 private _openingTime;
    uint256 private _closingTime;

    // Track whether the goal has been reached
    bool private _goalReached;

    // Track whether the tokens have been distributed
    bool private _tokensDistributed;

    // Track individual contributions
    mapping(address => uint256) private _contributions;

    // List of participants
    address[] private _participants;

    constructor(
        uint256 rate,
        address wallet,
        IERC20 token,
        uint256 openingTime,
        uint256 closingTime,
        uint256 goal
    )
        public
        Crowdsale(rate, wallet, token)
        TimedCrowdsale(openingTime, closingTime)
        RefundableCrowdsale(goal)
    {
        _rate = rate;
        _wallet = wallet;
        _token = token;
        _openingTime = openingTime;
        _closingTime = closingTime;
        _goal = goal;
    }

    /**
     * @dev Returns the amount of wei raised.
     */
    function weiRaised() public view returns (uint256) {
        return _weiRaised;
    }

    /**
     * @dev Returns the total contributions by an address.
     */
    function contributions(address beneficiary) public view returns (uint256) {
        return _contributions[beneficiary];
    }

    /**
     * @dev Returns the number of participants in the crowdsale.
     */
    function getParticipantCount() public view returns (uint256) {
        return _participants.length;
    }

    /**
     * @dev Returns the participant at the given index.
     */
    function getParticipant(uint256 index) public view returns (address) {
        require(index < _participants.length, "Invalid index");
        return _participants[index];
    }

    /**
     * @dev Extend crowdsale.
     * @param newClosingTime Crowdsale closing time
     */
    function extendTime(uint256 newClosingTime) public onlyOwner {
        require(!hasClosed(), "Crowdsale already closed");
        require(newClosingTime > _closingTime, "New closing time must be after current closing time");

        _extendTime(newClosingTime);
    }

    /**
     * @dev Overrides the buyTokens function to include logic for goal tracking and token distribution.
     * @param beneficiary Address to receive the tokens
     */
    function buyTokens(address beneficiary) public payable nonReentrant whenNotPaused {
        require(beneficiary != address(0), "Beneficiary address cannot be zero");
        require(msg.value != 0, "Value cannot be zero");
        require(isOpen(), "Crowdsale is not open");
        require(!hasClosed(), "Crowdsale has closed");

        uint256 weiAmount = msg.value;

        // Calculate token amount to be created
        uint256 tokens = weiAmount.mul(_rate);

        // Update wei raised
        _weiRaised = _weiRaised.add(weiAmount);

        // Update individual contributions
        _contributions[beneficiary] = _contributions[beneficiary].add(weiAmount);

        // Add participant to the list
        if (_contributions[beneficiary] == weiAmount) {
            _participants.push(beneficiary);
        }

        // Transfer tokens to beneficiary, but do not release them yet
        _token.safeTransfer(beneficiary, tokens);

        emit TokensPurchased(msg.sender, beneficiary, weiAmount, tokens);

        _processPurchase(beneficiary, weiAmount);
        _updatePurchasingState(beneficiary, weiAmount);
        _forwardFunds();
    }

    /**
     * @dev Overrides the _processPurchase function to include goal tracking logic.
     * @param beneficiary Address performing the token purchase
     * @param weiAmount Value in wei involved in the purchase
     */
    function _processPurchase(address beneficiary, uint256 weiAmount) internal override {
        super._processPurchase(beneficiary, weiAmount);

        // Check if goal has been reached
        if (_weiRaised >= _goal && !_goalReached) {
            _goalReached = true;
        }
    }

    /**
     * @dev Overrides the _finalization function to include token distribution and refund logic.
     */
    function _finalization() internal override {
        // If goal reached, distribute tokens
        if (_goalReached && !_tokensDistributed) {
            _deliverTokens();
            _tokensDistributed = true;
        }

        // If goal not reached, enable refund
        if (!_goalReached) {
            _enableRefunds();
        }

        super._finalization();
    }

    /**
     * @dev Overrides the _forwardFunds function to include logic for refundable crowdsale.
     */
    function _forwardFunds() internal override {
        if (!_goalReached) {
            super._forwardFunds();
        }
    }

    /**
     * @dev Overrides the _preValidatePurchase function to include goal tracking logic.
     * @param beneficiary Address performing the token purchase
     * @param weiAmount Value in wei involved in the purchase
     */
    function _preValidatePurchase(address beneficiary, uint256 weiAmount) internal view override whenNotPaused {
        super._preValidatePurchase(beneficiary, weiAmount);

        // Check if goal has been reached
        require(_weiRaised.add(weiAmount) <= _goal, "Purchase would exceed the goal");
    }

    /**
     * @dev Overrides the _processRefund function to refund participants.
     * @param beneficiary Address to receive the refund
     * @param amount Amount to be refunded
     */
    function _processRefund(address payable beneficiary, uint256 amount) internal override {
        super._processRefund(beneficiary, amount);

        // Remove participant from the list
        for (uint256 i = 0; i < _participants.length; i++) {
            if (_participants[i] == beneficiary) {
                _participants[i] = _participants[_participants.length - 1];
                _participants.pop();
                break;
            }
        }
    }
}
