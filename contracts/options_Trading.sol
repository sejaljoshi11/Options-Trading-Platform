// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract OptionsTradingPlatform is ReentrancyGuard, Ownable, Pausable {
    using SafeMath for uint256;

    enum OptionType { CALL, PUT }
    enum OptionState { ACTIVE, EXPIRED, EXERCISED, CANCELLED }

    struct Option {
        uint256 id;
        address creator;
        address buyer;
        address underlyingAsset;
        uint256 strikePrice;
        uint256 premium;
        uint256 expiry;
        uint256 amount;
        OptionType optionType;
        OptionState state;
        bool isCollateralized;
        uint256 createdAt;
        bool isAmerican; // true for American, false for European
    }

    struct PriceData {
        uint256 price;
        uint256 timestamp;
    }

    struct UserStats {
        uint256 totalOptionsCreated;
        uint256 totalOptionsBought;
        uint256 totalOptionsExercised;
        uint256 totalPremiumEarned;
        uint256 totalPremiumPaid;
        uint256 totalProfitFromExercise;
    }

    struct MarketData {
        uint256 totalVolume;
        uint256 totalOptionsCreated;
        uint256 totalOptionsExercised;
        uint256 activeOptionsCount;
    }

    mapping(uint256 => Option) public options;
    mapping(address => PriceData) public assetPrices;
    mapping(address => uint256[]) public userOptions;
    mapping(address => mapping(address => uint256)) public collateral;
    mapping(address => UserStats) public userStats;
    mapping(address => bool) public authorizedPriceFeeds;
    mapping(address => uint256) public assetMinimumPremium;
    mapping(uint256 => uint256[]) public optionBids; // optionId => [bidPrice, bidder]
    mapping(uint256 => mapping(address => uint256)) public userBids;
    mapping(address => uint256) public userReputationScore;
    
    uint256 public optionCounter;
    uint256 public constant EXERCISE_WINDOW = 1 hours;
    uint256 public constant PRICE_VALIDITY_DURATION = 1 hours;
    uint256 public platformFee = 100; // 1% = 100 basis points
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_REPUTATION_SCORE = 0;
    uint256 public constant MAX_REPUTATION_SCORE = 1000;
    
    MarketData public marketData;
    bool public biddingEnabled = true;
    bool public reputationSystemEnabled = true;
    uint256 public maxOptionDuration = 365 days;
    uint256 public minOptionDuration = 1 hours;

    event OptionCreated(
        uint256 indexed optionId,
        address indexed creator,
        address indexed underlyingAsset,
        uint256 strikePrice,
        uint256 premium,
        uint256 expiry,
        OptionType optionType,
        bool isAmerican
    );

    event OptionPurchased(
        uint256 indexed optionId,
        address indexed buyer,
        uint256 premium
    );

    event OptionExercised(
        uint256 indexed optionId,
        address indexed buyer,
        uint256 profit
    );

    event OptionCancelled(
        uint256 indexed optionId,
        address indexed creator
    );

    event OptionExpired(
        uint256 indexed optionId
    );

    event PriceUpdated(
        address indexed asset,
        uint256 price,
        uint256 timestamp
    );

    event CollateralDeposited(
        address indexed user,
        address indexed asset,
        uint256 amount
    );

    event CollateralWithdrawn(
        address indexed user,
        address indexed asset,
        uint256 amount
    );

    event BidPlaced(
        uint256 indexed optionId,
        address indexed bidder,
        uint256 bidAmount
    );

    event BidWithdrawn(
        uint256 indexed optionId,
        address indexed bidder,
        uint256 bidAmount
    );

    event ReputationUpdated(
        address indexed user,
        uint256 newScore,
        string reason
    );

    modifier optionExists(uint256 _optionId) {
        require(_optionId < optionCounter, "Option does not exist");
        _;
    }

    modifier onlyOptionCreator(uint256 _optionId) {
        require(options[_optionId].creator == msg.sender, "Only option creator can perform this action");
        _;
    }

    modifier onlyOptionBuyer(uint256 _optionId) {
        require(options[_optionId].buyer == msg.sender, "Only option buyer can perform this action");
        _;
    }

    modifier validPrice(address _asset) {
        require(
            assetPrices[_asset].timestamp > 0 && 
            block.timestamp.sub(assetPrices[_asset].timestamp) <= PRICE_VALIDITY_DURATION,
            "Price data is stale or unavailable"
        );
        _;
    }

    modifier onlyAuthorizedPriceFeed() {
        require(authorizedPriceFeeds[msg.sender] || msg.sender == owner(), "Not authorized to update prices");
        _;
    }

    constructor() Ownable(msg.sender) {
        authorizedPriceFeeds[msg.sender] = true;
    }

    /**
     * @dev Creates a new option contract with enhanced features
     */
    function createOption(
        address _underlyingAsset,
        uint256 _strikePrice,
        uint256 _premium,
        uint256 _expiry,
        uint256 _amount,
        OptionType _optionType,
        bool _isAmerican
    ) external payable nonReentrant whenNotPaused validPrice(_underlyingAsset) {
        require(_underlyingAsset != address(0), "Invalid asset address");
        require(_strikePrice > 0, "Strike price must be greater than 0");
        require(_premium >= assetMinimumPremium[_underlyingAsset], "Premium below minimum");
        require(_expiry > block.timestamp.add(minOptionDuration), "Expiry too soon");
        require(_expiry <= block.timestamp.add(maxOptionDuration), "Expiry too far");
        require(_amount > 0, "Amount must be greater than 0");

        uint256 optionId = optionCounter++;
        uint256 requiredCollateral = calculateRequiredCollateral(_strikePrice, _amount, _optionType);

        // Enhanced collateral handling
        if (_optionType == OptionType.CALL) {
            require(
                collateral[msg.sender][_underlyingAsset] >= _amount,
                "Insufficient collateral for CALL option"
            );
            collateral[msg.sender][_underlyingAsset] = collateral[msg.sender][_underlyingAsset].sub(_amount);
        } else {
            require(msg.value >= requiredCollateral, "Insufficient ETH collateral for PUT option");
        }

        options[optionId] = Option({
            id: optionId,
            creator: msg.sender,
            buyer: address(0),
            underlyingAsset: _underlyingAsset,
            strikePrice: _strikePrice,
            premium: _premium,
            expiry: _expiry,
            amount: _amount,
            optionType: _optionType,
            state: OptionState.ACTIVE,
            isCollateralized: true,
            createdAt: block.timestamp,
            isAmerican: _isAmerican
        });

        userOptions[msg.sender].push(optionId);
        userStats[msg.sender].totalOptionsCreated++;
        marketData.totalOptionsCreated++;
        marketData.activeOptionsCount++;

        // Update reputation for creating options
        if (reputationSystemEnabled) {
            _updateReputation(msg.sender, 5, "Option created");
        }

        emit OptionCreated(
            optionId,
            msg.sender,
            _underlyingAsset,
            _strikePrice,
            _premium,
            _expiry,
            _optionType,
            _isAmerican
        );
    }

    /**
     * @dev Enhanced option purchase with reputation checks
     */
    function purchaseOption(uint256 _optionId) external payable nonReentrant whenNotPaused optionExists(_optionId) {
        Option storage option = options[_optionId];
        require(option.state == OptionState.ACTIVE, "Option is not active");
        require(option.buyer == address(0), "Option already purchased");
        require(block.timestamp < option.expiry, "Option has expired");
        require(msg.sender != option.creator, "Cannot buy your own option");

        // Reputation check
        if (reputationSystemEnabled) {
            require(userReputationScore[msg.sender] >= MIN_REPUTATION_SCORE, "Insufficient reputation");
        }

        uint256 totalCost = option.premium.add(option.premium.mul(platformFee).div(BASIS_POINTS));
        require(msg.value >= totalCost, "Insufficient payment");

        option.buyer = msg.sender;
        userOptions[msg.sender].push(_optionId);
        userStats[msg.sender].totalOptionsBought++;
        userStats[msg.sender].totalPremiumPaid = userStats[msg.sender].totalPremiumPaid.add(option.premium);
        userStats[option.creator].totalPremiumEarned = userStats[option.creator].totalPremiumEarned.add(option.premium);
        marketData.totalVolume = marketData.totalVolume.add(option.premium);

        // Transfer premium to option creator
        uint256 creatorPayment = option.premium;
        uint256 platformPayment = totalCost.sub(creatorPayment);

        (bool success1, ) = option.creator.call{value: creatorPayment}("");
        require(success1, "Payment to creator failed");

        if (platformPayment > 0) {
            (bool success2, ) = owner().call{value: platformPayment}("");
            require(success2, "Platform fee transfer failed");
        }

        // Refund excess payment
        if (msg.value > totalCost) {
            (bool success3, ) = msg.sender.call{value: msg.value.sub(totalCost)}("");
            require(success3, "Refund failed");
        }

        // Update reputation
        if (reputationSystemEnabled) {
            _updateReputation(msg.sender, 3, "Option purchased");
        }

        emit OptionPurchased(_optionId, msg.sender, option.premium);
    }

    /**
     * @dev Enhanced exercise function with American/European option support
     */
    function exerciseOption(uint256 _optionId) external nonReentrant whenNotPaused optionExists(_optionId) onlyOptionBuyer(_optionId) validPrice(options[_optionId].underlyingAsset) {
        Option storage option = options[_optionId];
        require(option.state == OptionState.ACTIVE, "Option is not active");
        
        // Check exercise conditions based on option type
        if (option.isAmerican) {
            require(block.timestamp <= option.expiry, "Option has expired");
        } else {
            // European option can only be exercised at expiry
            require(
                block.timestamp >= option.expiry.sub(EXERCISE_WINDOW) && 
                block.timestamp <= option.expiry.add(EXERCISE_WINDOW),
                "European option can only be exercised at expiry"
            );
        }

        uint256 currentPrice = assetPrices[option.underlyingAsset].price;
        uint256 profit = calculateExerciseProfit(option, currentPrice);

        option.state = OptionState.EXERCISED;
        userStats[msg.sender].totalOptionsExercised++;
        userStats[msg.sender].totalProfitFromExercise = userStats[msg.sender].totalProfitFromExercise.add(profit);
        marketData.totalOptionsExercised++;
        marketData.activeOptionsCount--;

        if (profit > 0) {
            require(address(this).balance >= profit, "Insufficient contract balance");
            (bool success, ) = msg.sender.call{value: profit}("");
            require(success, "Profit transfer failed");
        }

        // Handle collateral release
        _releaseCollateral(option, profit);

        // Update reputation
        if (reputationSystemEnabled) {
            _updateReputation(msg.sender, 10, "Option exercised");
        }

        emit OptionExercised(_optionId, msg.sender, profit);
    }

    /**
     * @dev Cancel an option (only creator, before purchase)
     */
    function cancelOption(uint256 _optionId) external nonReentrant optionExists(_optionId) onlyOptionCreator(_optionId) {
        Option storage option = options[_optionId];
        require(option.state == OptionState.ACTIVE, "Option is not active");
        require(option.buyer == address(0), "Option already purchased");

        option.state = OptionState.CANCELLED;
        marketData.activeOptionsCount--;

        // Return collateral
        if (option.optionType == OptionType.CALL) {
            collateral[msg.sender][option.underlyingAsset] = collateral[msg.sender][option.underlyingAsset].add(option.amount);
        } else {
            uint256 collateralAmount = calculateRequiredCollateral(option.strikePrice, option.amount, option.optionType);
            (bool success, ) = msg.sender.call{value: collateralAmount}("");
            require(success, "Collateral return failed");
        }

        emit OptionCancelled(_optionId, msg.sender);
    }

    /**
     * @dev Batch expire options (can be called by anyone)
     */
    function batchExpireOptions(uint256[] calldata _optionIds) external {
        for (uint256 i = 0; i < _optionIds.length; i++) {
            _expireOption(_optionIds[i]);
        }
    }

    /**
     * @dev Place a bid on an option
     */
    function placeBid(uint256 _optionId, uint256 _bidAmount) external payable nonReentrant optionExists(_optionId) {
        require(biddingEnabled, "Bidding is disabled");
        require(msg.value >= _bidAmount, "Insufficient payment for bid");
        require(_bidAmount > 0, "Bid must be greater than 0");
        
        Option storage option = options[_optionId];
        require(option.state == OptionState.ACTIVE, "Option is not active");
        require(option.buyer == address(0), "Option already purchased");
        require(msg.sender != option.creator, "Cannot bid on your own option");

        // Refund previous bid if exists
        if (userBids[_optionId][msg.sender] > 0) {
            (bool success, ) = msg.sender.call{value: userBids[_optionId][msg.sender]}("");
            require(success, "Previous bid refund failed");
        }

        userBids[_optionId][msg.sender] = _bidAmount;
        
        // Refund excess payment
        if (msg.value > _bidAmount) {
            (bool success, ) = msg.sender.call{value: msg.value.sub(_bidAmount)}("");
            require(success, "Excess bid refund failed");
        }

        emit BidPlaced(_optionId, msg.sender, _bidAmount);
    }

    /**
     * @dev Accept a bid on an option
     */
    function acceptBid(uint256 _optionId, address _bidder) external nonReentrant optionExists(_optionId) onlyOptionCreator(_optionId) {
        require(biddingEnabled, "Bidding is disabled");
        Option storage option = options[_optionId];
        require(option.state == OptionState.ACTIVE, "Option is not active");
        require(option.buyer == address(0), "Option already purchased");
        require(userBids[_optionId][_bidder] > 0, "No valid bid from this bidder");

        uint256 bidAmount = userBids[_optionId][_bidder];
        uint256 platformFeeAmount = bidAmount.mul(platformFee).div(BASIS_POINTS);
        uint256 creatorPayment = bidAmount.sub(platformFeeAmount);

        option.buyer = _bidder;
        option.premium = bidAmount;
        userOptions[_bidder].push(_optionId);
        userStats[_bidder].totalOptionsBought++;
        userStats[_bidder].totalPremiumPaid = userStats[_bidder].totalPremiumPaid.add(bidAmount);
        userStats[msg.sender].totalPremiumEarned = userStats[msg.sender].totalPremiumEarned.add(bidAmount);
        marketData.totalVolume = marketData.totalVolume.add(bidAmount);

        // Clear all bids for this option
        userBids[_optionId][_bidder] = 0;

        // Transfer payments
        (bool success1, ) = msg.sender.call{value: creatorPayment}("");
        require(success1, "Payment to creator failed");

        if (platformFeeAmount > 0) {
            (bool success2, ) = owner().call{value: platformFeeAmount}("");
            require(success2, "Platform fee transfer failed");
        }

        emit OptionPurchased(_optionId, _bidder, bidAmount);
    }

    /**
     * @dev Withdraw a bid
     */
    function withdrawBid(uint256 _optionId) external nonReentrant optionExists(_optionId) {
        require(userBids[_optionId][msg.sender] > 0, "No bid to withdraw");
        
        uint256 bidAmount = userBids[_optionId][msg.sender];
        userBids[_optionId][msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: bidAmount}("");
        require(success, "Bid withdrawal failed");

        emit BidWithdrawn(_optionId, msg.sender, bidAmount);
    }

    /**
     * @dev Calculate exercise profit
     */
    function calculateExerciseProfit(Option memory option, uint256 currentPrice) public pure returns (uint256) {
        uint256 profit = 0;
        
        if (option.optionType == OptionType.CALL) {
            if (currentPrice > option.strikePrice) {
                profit = currentPrice.sub(option.strikePrice).mul(option.amount).div(1e18);
            }
        } else {
            if (currentPrice < option.strikePrice) {
                profit = option.strikePrice.sub(currentPrice).mul(option.amount).div(1e18);
            }
        }
        
        return profit;
    }

    /**
     * @dev Internal function to expire an option
     */
    function _expireOption(uint256 _optionId) internal {
        if (_optionId >= optionCounter) return;
        
        Option storage option = options[_optionId];
        if (option.state != OptionState.ACTIVE) return;
        if (block.timestamp <= option.expiry.add(EXERCISE_WINDOW)) return;

        option.state = OptionState.EXPIRED;
        marketData.activeOptionsCount--;

        // Return collateral to creator
        if (option.optionType == OptionType.CALL) {
            collateral[option.creator][option.underlyingAsset] = collateral[option.creator][option.underlyingAsset].add(option.amount);
        } else {
            uint256 collateralAmount = calculateRequiredCollateral(option.strikePrice, option.amount, option.optionType);
            (bool success, ) = option.creator.call{value: collateralAmount}("");
            require(success, "Collateral return failed");
        }

        emit OptionExpired(_optionId);
    }

    /**
     * @dev Internal function to release collateral
     */
    function _releaseCollateral(Option memory option, uint256 profit) internal {
        if (profit == 0) {
            if (option.optionType == OptionType.CALL) {
                collateral[option.creator][option.underlyingAsset] = collateral[option.creator][option.underlyingAsset].add(option.amount);
            } else {
                uint256 collateralAmount = calculateRequiredCollateral(option.strikePrice, option.amount, option.optionType);
                (bool success, ) = option.creator.call{value: collateralAmount}("");
                require(success, "Collateral return failed");
            }
        }
    }

    /**
     * @dev Update user reputation
     */
    function _updateReputation(address user, uint256 points, string memory reason) internal {
        uint256 currentScore = userReputationScore[user];
        uint256 newScore = currentScore.add(points);
        
        if (newScore > MAX_REPUTATION_SCORE) {
            newScore = MAX_REPUTATION_SCORE;
        }
        
        userReputationScore[user] = newScore;
        
        emit ReputationUpdated(user, newScore, reason);
    }

    // Admin functions
    function updateAssetPrice(address _asset, uint256 _price) external onlyAuthorizedPriceFeed {
        require(_asset != address(0), "Invalid asset address");
        require(_price > 0, "Price must be greater than 0");
        
        assetPrices[_asset] = PriceData({
            price: _price,
            timestamp: block.timestamp
        });

        emit PriceUpdated(_asset, _price, block.timestamp);
    }

    function setAuthorizedPriceFeed(address _feed, bool _authorized) external onlyOwner {
        authorizedPriceFeeds[_feed] = _authorized;
    }

    function setAssetMinimumPremium(address _asset, uint256 _minPremium) external onlyOwner {
        assetMinimumPremium[_asset] = _minPremium;
    }

    function setBiddingEnabled(bool _enabled) external onlyOwner {
        biddingEnabled = _enabled;
    }

    function setReputationSystemEnabled(bool _enabled) external onlyOwner {
        reputationSystemEnabled = _enabled;
    }

    function setOptionDurationLimits(uint256 _minDuration, uint256 _maxDuration) external onlyOwner {
        require(_minDuration < _maxDuration, "Invalid duration limits");
        minOptionDuration = _minDuration;
        maxOptionDuration = _maxDuration;
    }

    function pauseContract() external onlyOwner {
        _pause();
    }

    function unpauseContract() external onlyOwner {
        _unpause();
    }

    // Enhanced collateral functions
    function depositCollateral(address _asset, uint256 _amount) external {
        require(_asset != address(0), "Invalid asset address");
        require(_amount > 0, "Amount must be greater than 0");
        
        IERC20 token = IERC20(_asset);
        require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        
        collateral[msg.sender][_asset] = collateral[msg.sender][_asset].add(_amount);
        
        emit CollateralDeposited(msg.sender, _asset, _amount);
    }

    function withdrawCollateral(address _asset, uint256 _amount) external nonReentrant {
        require(_asset != address(0), "Invalid asset address");
        require(_amount > 0, "Amount must be greater than 0");
        require(collateral[msg.sender][_asset] >= _amount, "Insufficient collateral");
        
        collateral[msg.sender][_asset] = collateral[msg.sender][_asset].sub(_amount);
        
        IERC20 token = IERC20(_asset);
        require(token.transfer(msg.sender, _amount), "Transfer failed");
        
        emit CollateralWithdrawn(msg.sender, _asset, _amount);
    }

    function calculateRequiredCollateral(
        uint256 _strikePrice,
        uint256 _amount,
        OptionType _optionType
    ) public pure returns (uint256) {
        if (_optionType == OptionType.CALL) {
            return _amount;
        } else {
            return _strikePrice.mul(_amount).div(1e18);
        }
    }

    // Enhanced view functions
    function getOption(uint256 _optionId) external view optionExists(_optionId) returns (Option memory) {
        return options[_optionId];
    }

    function getUserOptions(address _user) external view returns (uint256[] memory) {
        return userOptions[_user];
    }

    function getUserStats(address _user) external view returns (UserStats memory) {
        return userStats[_user];
    }

    function getMarketData() external view returns (MarketData memory) {
        return marketData;
    }

    function getActiveOptions() external view returns (uint256[] memory) {
        uint256[] memory activeOptions = new uint256[](marketData.activeOptionsCount);
        uint256 count = 0;
        
        for (uint256 i = 0; i < optionCounter; i++) {
            if (options[i].state == OptionState.ACTIVE) {
                activeOptions[count] = i;
                count++;
            }
        }
        
        return activeOptions;
    }

    function getAssetPrice(address _asset) external view returns (uint256, uint256) {
        PriceData memory data = assetPrices[_asset];
        return (data.price, data.timestamp);
    }

    function getUserCollateral(address _user, address _asset) external view returns (uint256) {
        return collateral[_user][_asset];
    }

    function getUserBid(uint256 _optionId, address _user) external view returns (uint256) {
        return userBids[_optionId][_user];
    }

    function isOptionInMoney(uint256 _optionId) external view optionExists(_optionId) validPrice(options[_optionId].underlyingAsset) returns (bool) {
        Option memory option = options[_optionId];
        uint256 currentPrice = assetPrices[option.underlyingAsset].price;
        
        if (option.optionType == OptionType.CALL) {
            return currentPrice > option.strikePrice;
        } else {
            return currentPrice < option.strikePrice;
        }
    }

    function getOptionTimeToExpiry(uint256 _optionId) external view optionExists(_optionId) returns (uint256) {
        Option memory option = options[_optionId];
        if (block.timestamp >= option.expiry) {
            return 0;
        }
        return option.expiry.sub(block.timestamp);
    }

    // Emergency functions
    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 1000, "Fee cannot exceed 10%");
        platformFee = _fee;
    }

    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Emergency withdrawal failed");
    }

    receive() external payable {}
}
