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
        bool isAmerican;
        uint256 impliedVolatility; // New: IV for pricing
        bool isSpread; // New: For spread options
        uint256 spreadStrike2; // New: Second strike for spreads
    }

    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 volatility; // New: Historical volatility
    }

    struct UserStats {
        uint256 totalOptionsCreated;
        uint256 totalOptionsBought;
        uint256 totalOptionsExercised;
        uint256 totalPremiumEarned;
        uint256 totalPremiumPaid;
        uint256 totalProfitFromExercise;
        uint256 winRate; // New: Success rate percentage
        uint256 averageHoldTime; // New: Average time holding options
    }

    struct MarketData {
        uint256 totalVolume;
        uint256 totalOptionsCreated;
        uint256 totalOptionsExercised;
        uint256 activeOptionsCount;
        uint256 totalTradingFees; // New: Accumulated trading fees
    }

    // New: Pool structure for liquidity provision
    struct LiquidityPool {
        uint256 totalLiquidity;
        uint256 availableLiquidity;
        mapping(address => uint256) userShares;
        uint256 totalShares;
        uint256 feeRate; // Pool fee rate
    }

    // New: Flash loan structure
    struct FlashLoan {
        uint256 amount;
        uint256 fee;
        address borrower;
        bool active;
    }

    // New: Insurance structure
    struct Insurance {
        uint256 premium;
        uint256 coverage;
        uint256 expiry;
        bool isActive;
    }

    mapping(uint256 => Option) public options;
    mapping(address => PriceData) public assetPrices;
    mapping(address => uint256[]) public userOptions;
    mapping(address => mapping(address => uint256)) public collateral;
    mapping(address => UserStats) public userStats;
    mapping(address => bool) public authorizedPriceFeeds;
    mapping(address => uint256) public assetMinimumPremium;
    mapping(uint256 => uint256[]) public optionBids;
    mapping(uint256 => mapping(address => uint256)) public userBids;
    mapping(address => uint256) public userReputationScore;
    
    // New mappings
    mapping(address => LiquidityPool) public liquidityPools; // Asset => Pool
    mapping(address => mapping(address => uint256)) public userPoolShares; // User => Asset => Shares
    mapping(uint256 => FlashLoan) public flashLoans;
    mapping(address => mapping(uint256 => Insurance)) public userInsurance; // User => OptionId => Insurance
    mapping(address => uint256[]) public priceHistory; // Asset => Price history
    mapping(uint256 => uint256[]) public optionChain; // Strike => Option IDs
    mapping(address => bool) public whitelistedAssets;
    mapping(address => uint256) public assetTradingVolume; // 24h trading volume per asset
    mapping(address => uint256) public lastActivityTime; // User activity tracking
    mapping(uint256 => bool) public autoExerciseEnabled; // Option ID => Auto-exercise status
    mapping(address => uint256) public referralRewards; // Referral system
    mapping(address => address) public referrals; // User => Referrer
    
    uint256 public optionCounter;
    uint256 public flashLoanCounter;
    uint256 public constant EXERCISE_WINDOW = 1 hours;
    uint256 public constant PRICE_VALIDITY_DURATION = 1 hours;
    uint256 public platformFee = 100; // 1% = 100 basis points
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_REPUTATION_SCORE = 0;
    uint256 public constant MAX_REPUTATION_SCORE = 1000;
    
    // New constants
    uint256 public constant FLASH_LOAN_FEE = 30; // 0.3%
    uint256 public constant INSURANCE_RATE = 200; // 2%
    uint256 public constant REFERRAL_BONUS = 50; // 0.5%
    uint256 public liquidityIncentiveRate = 500; // 5% APY for LP tokens
    
    MarketData public marketData;
    bool public biddingEnabled = true;
    bool public reputationSystemEnabled = true;
    bool public autoExerciseEnabled = true; // New: Global auto-exercise toggle
    bool public flashLoansEnabled = true; // New: Flash loans toggle
    bool public insuranceEnabled = true; // New: Insurance toggle
    uint256 public maxOptionDuration = 365 days;
    uint256 public minOptionDuration = 1 hours;

    // New events
    event LiquidityProvided(address indexed provider, address indexed asset, uint256 amount, uint256 shares);
    event LiquidityWithdrawn(address indexed provider, address indexed asset, uint256 amount, uint256 shares);
    event FlashLoanExecuted(uint256 indexed loanId, address indexed borrower, uint256 amount, uint256 fee);
    event InsurancePurchased(address indexed user, uint256 indexed optionId, uint256 premium, uint256 coverage);
    event AutoExerciseExecuted(uint256 indexed optionId, address indexed buyer, uint256 profit);
    event VolatilityUpdated(address indexed asset, uint256 newVolatility);
    event SpreadOptionCreated(uint256 indexed optionId, uint256 strike1, uint256 strike2);
    event ReferralRewardPaid(address indexed referrer, address indexed referee, uint256 amount);
    event AssetWhitelisted(address indexed asset, bool status);

    // Existing events...
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

    // New modifiers
    modifier onlyWhitelistedAsset(address _asset) {
        require(whitelistedAssets[_asset] || msg.sender == owner(), "Asset not whitelisted");
        _;
    }

    modifier flashLoansOnly() {
        require(flashLoansEnabled, "Flash loans disabled");
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
    ) external payable nonReentrant whenNotPaused validPrice(_underlyingAsset) onlyWhitelistedAsset(_underlyingAsset) {
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

        // Calculate implied volatility based on premium and current price
        uint256 impliedVol = calculateImpliedVolatility(_strikePrice, _premium, _expiry);

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
            isAmerican: _isAmerican,
            impliedVolatility: impliedVol,
            isSpread: false,
            spreadStrike2: 0
        });

        // Add to option chain
        optionChain[_strikePrice].push(optionId);
        
        userOptions[msg.sender].push(optionId);
        userStats[msg.sender].totalOptionsCreated++;
        marketData.totalOptionsCreated++;
        marketData.activeOptionsCount++;
        lastActivityTime[msg.sender] = block.timestamp;

        // Update reputation for creating options
        if (reputationSystemEnabled) {
            _updateReputation(msg.sender, 5, "Option created");
        }

        // Handle referral rewards
        _handleReferralReward(msg.sender, _premium);

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
     * @dev Create spread option (bull call spread, bear put spread, etc.)
     */
    function createSpreadOption(
        address _underlyingAsset,
        uint256 _strikePrice1,
        uint256 _strikePrice2,
        uint256 _premium,
        uint256 _expiry,
        uint256 _amount,
        OptionType _optionType,
        bool _isAmerican
    ) external payable nonReentrant whenNotPaused validPrice(_underlyingAsset) onlyWhitelistedAsset(_underlyingAsset) {
        require(_strikePrice1 != _strikePrice2, "Strike prices must be different");
        require(_strikePrice1 > 0 && _strikePrice2 > 0, "Invalid strike prices");
        
        uint256 optionId = optionCounter++;
        uint256 requiredCollateral = calculateSpreadCollateral(_strikePrice1, _strikePrice2, _amount, _optionType);
        require(msg.value >= requiredCollateral, "Insufficient collateral");

        options[optionId] = Option({
            id: optionId,
            creator: msg.sender,
            buyer: address(0),
            underlyingAsset: _underlyingAsset,
            strikePrice: _strikePrice1,
            premium: _premium,
            expiry: _expiry,
            amount: _amount,
            optionType: _optionType,
            state: OptionState.ACTIVE,
            isCollateralized: true,
            createdAt: block.timestamp,
            isAmerican: _isAmerican,
            impliedVolatility: calculateImpliedVolatility(_strikePrice1, _premium, _expiry),
            isSpread: true,
            spreadStrike2: _strikePrice2
        });

        userOptions[msg.sender].push(optionId);
        userStats[msg.sender].totalOptionsCreated++;
        marketData.totalOptionsCreated++;
        marketData.activeOptionsCount++;

        emit SpreadOptionCreated(optionId, _strikePrice1, _strikePrice2);
    }

    /**
     * @dev Provide liquidity to earn fees
     */
    function provideLiquidity(address _asset, uint256 _amount) external payable nonReentrant onlyWhitelistedAsset(_asset) {
        require(_amount > 0, "Amount must be greater than 0");
        
        LiquidityPool storage pool = liquidityPools[_asset];
        
        // Calculate shares based on pool ratio or 1:1 for first deposit
        uint256 shares;
        if (pool.totalShares == 0) {
            shares = _amount;
        } else {
            shares = _amount.mul(pool.totalShares).div(pool.totalLiquidity);
        }

        // Handle ETH or ERC20 deposits
        if (_asset == address(0)) {
            require(msg.value >= _amount, "Insufficient ETH sent");
        } else {
            IERC20 token = IERC20(_asset);
            require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        }

        pool.totalLiquidity = pool.totalLiquidity.add(_amount);
        pool.availableLiquidity = pool.availableLiquidity.add(_amount);
        pool.userShares[msg.sender] = pool.userShares[msg.sender].add(shares);
        pool.totalShares = pool.totalShares.add(shares);
        userPoolShares[msg.sender][_asset] = userPoolShares[msg.sender][_asset].add(shares);

        emit LiquidityProvided(msg.sender, _asset, _amount, shares);
    }

    /**
     * @dev Withdraw liquidity and earned fees
     */
    function withdrawLiquidity(address _asset, uint256 _shares) external nonReentrant {
        require(_shares > 0, "Shares must be greater than 0");
        
        LiquidityPool storage pool = liquidityPools[_asset];
        require(pool.userShares[msg.sender] >= _shares, "Insufficient shares");
        
        uint256 amount = _shares.mul(pool.totalLiquidity).div(pool.totalShares);
        require(pool.availableLiquidity >= amount, "Insufficient liquidity");
        
        pool.userShares[msg.sender] = pool.userShares[msg.sender].sub(_shares);
        pool.totalShares = pool.totalShares.sub(_shares);
        pool.totalLiquidity = pool.totalLiquidity.sub(amount);
        pool.availableLiquidity = pool.availableLiquidity.sub(amount);
        userPoolShares[msg.sender][_asset] = userPoolShares[msg.sender][_asset].sub(_shares);

        // Transfer funds back
        if (_asset == address(0)) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20 token = IERC20(_asset);
            require(token.transfer(msg.sender, amount), "Token transfer failed");
        }

        emit LiquidityWithdrawn(msg.sender, _asset, amount, _shares);
    }

    /**
     * @dev Execute flash loan
     */
    function executeFlashLoan(
        address _asset,
        uint256 _amount,
        bytes calldata _data
    ) external nonReentrant flashLoansOnly {
        require(_amount > 0, "Amount must be greater than 0");
        require(whitelistedAssets[_asset], "Asset not supported");
        
        LiquidityPool storage pool = liquidityPools[_asset];
        require(pool.availableLiquidity >= _amount, "Insufficient liquidity");
        
        uint256 loanId = flashLoanCounter++;
        uint256 fee = _amount.mul(FLASH_LOAN_FEE).div(BASIS_POINTS);
        
        flashLoans[loanId] = FlashLoan({
            amount: _amount,
            fee: fee,
            borrower: msg.sender,
            active: true
        });
        
        pool.availableLiquidity = pool.availableLiquidity.sub(_amount);
        
        // Transfer loan amount
        if (_asset == address(0)) {
            (bool success, ) = msg.sender.call{value: _amount}("");
            require(success, "Loan transfer failed");
        } else {
            IERC20 token = IERC20(_asset);
            require(token.transfer(msg.sender, _amount), "Loan transfer failed");
        }
        
        // Execute borrower's logic
        (bool callSuccess, ) = msg.sender.call(_data);
        require(callSuccess, "Flash loan execution failed");
        
        // Repay loan + fee
        uint256 repayAmount = _amount.add(fee);
        if (_asset == address(0)) {
            require(address(this).balance >= repayAmount, "Insufficient repayment");
        } else {
            IERC20 token = IERC20(_asset);
            require(token.transferFrom(msg.sender, address(this), repayAmount), "Repayment failed");
        }
        
        pool.availableLiquidity = pool.availableLiquidity.add(_amount);
        pool.totalLiquidity = pool.totalLiquidity.add(fee); // Fee stays in pool
        flashLoans[loanId].active = false;
        
        emit FlashLoanExecuted(loanId, msg.sender, _amount, fee);
    }

    /**
     * @dev Purchase insurance for an option
     */
    function purchaseInsurance(uint256 _optionId, uint256 _coverage) external payable nonReentrant optionExists(_optionId) {
        require(insuranceEnabled, "Insurance disabled");
        require(_coverage > 0, "Coverage must be greater than 0");
        
        Option memory option = options[_optionId];
        require(option.buyer == msg.sender, "Only option buyer can purchase insurance");
        require(option.state == OptionState.ACTIVE, "Option not active");
        
        uint256 insurancePremium = _coverage.mul(INSURANCE_RATE).div(BASIS_POINTS);
        require(msg.value >= insurancePremium, "Insufficient insurance premium");
        
        userInsurance[msg.sender][_optionId] = Insurance({
            premium: insurancePremium,
            coverage: _coverage,
            expiry: option.expiry,
            isActive: true
        });
        
        emit InsurancePurchased(msg.sender, _optionId, insurancePremium, _coverage);
    }

    /**
     * @dev Auto-exercise option if profitable at expiry
     */
    function enableAutoExercise(uint256 _optionId) external optionExists(_optionId) onlyOptionBuyer(_optionId) {
        autoExerciseEnabled[_optionId] = true;
    }

    /**
     * @dev Check and execute auto-exercise for options
     */
    function executeAutoExercise(uint256 _optionId) external optionExists(_optionId) validPrice(options[_optionId].underlyingAsset) {
        Option storage option = options[_optionId];
        require(autoExerciseEnabled[_optionId], "Auto-exercise not enabled");
        require(option.state == OptionState.ACTIVE, "Option not active");
        require(block.timestamp >= option.expiry.sub(EXERCISE_WINDOW), "Too early for auto-exercise");
        
        uint256 currentPrice = assetPrices[option.underlyingAsset].price;
        uint256 profit = calculateExerciseProfit(option, currentPrice);
        
        if (profit > 0) {
            option.state = OptionState.EXERCISED;
            userStats[option.buyer].totalOptionsExercised++;
            userStats[option.buyer].totalProfitFromExercise = userStats[option.buyer].totalProfitFromExercise.add(profit);
            marketData.totalOptionsExercised++;
            marketData.activeOptionsCount--;
            
            (bool success, ) = option.buyer.call{value: profit}("");
            require(success, "Auto-exercise profit transfer failed");
            
            _releaseCollateral(option, profit);
            
            emit AutoExerciseExecuted(_optionId, option.buyer, profit);
        }
    }

    /**
     * @dev Set referral relationship
     */
    function setReferral(address _referrer) external {
        require(_referrer != msg.sender, "Cannot refer yourself");
        require(referrals[msg.sender] == address(0), "Referral already set");
        referrals[msg.sender] = _referrer;
    }

    /**
     * @dev Calculate Black-Scholes option price (simplified)
     */
    function calculateOptionPrice(
        uint256 _currentPrice,
        uint256 _strikePrice,
        uint256 _timeToExpiry,
        uint256 _volatility,
        OptionType _optionType
    ) public pure returns (uint256) {
        // Simplified Black-Scholes calculation
        // In production, use a proper mathematical library
        
        uint256 intrinsicValue;
        if (_optionType == OptionType.CALL) {
            intrinsicValue = _currentPrice > _strikePrice ? _currentPrice.sub(_strikePrice) : 0;
        } else {
            intrinsicValue = _strikePrice > _currentPrice ? _strikePrice.sub(_currentPrice) : 0;
        }
        
        // Time value calculation (simplified)
        uint256 timeValue = _volatility.mul(_timeToExpiry).div(365 days).mul(_currentPrice).div(100);
        
        return intrinsicValue.add(timeValue);
    }

    /**
     * @dev Calculate implied volatility (simplified)
     */
    function calculateImpliedVolatility(
        uint256 _strikePrice,
        uint256 _premium,
        uint256 _expiry
    ) public view returns (uint256) {
        // Simplified IV calculation
        uint256 timeToExpiry = _expiry > block.timestamp ? _expiry.sub(block.timestamp) : 0;
        if (timeToExpiry == 0) return 0;
        
        // Basic IV estimation based on premium and time
        return _premium.mul(100).div(timeToExpiry.div(1 days).add(1));
    }

    /**
     * @dev Calculate required collateral for spread options
     */
    function calculateSpreadCollateral(
        uint256 _strike1,
        uint256 _strike2,
        uint256 _amount,
        OptionType _optionType
    ) public pure returns (uint256) {
        uint256 spreadWidth = _strike1 > _strike2 ? _strike1.sub(_strike2) : _strike2.sub(_strike1);
        return spreadWidth.mul(_amount).div(1e18);
    }

    /**
     * @dev Handle referral rewards
     */
    function _handleReferralReward(address _user, uint256 _premium) internal {
        address referrer = referrals[_user];
        if (referrer != address(0) && referrer != _user) {
            uint256 reward = _premium.mul(REFERRAL_BONUS).div(BASIS_POINTS);
            referralRewards[referrer] = referralRewards[referrer].add(reward);
            
            emit ReferralRewardPaid(referrer, _user, reward);
        }
    }

    /**
     * @dev Claim referral rewards
     */
    function claimReferralRewards() external nonReentrant {
        uint256 reward = referralRewards[msg.sender];
        require(reward > 0, "No rewards to claim");
        
        referralRewards[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: reward}("");
        require(success, "Reward transfer failed");
    }

    // Enhanced view functions
    
    /**
     * @dev Get option chain for a specific strike price
     */
    function getOptionChain(uint256 _strikePrice) external view returns (uint256[] memory) {
        return optionChain[_strikePrice];
    }

    /**
     * @dev Get liquidity pool info
     */
    function getPoolInfo(address _asset) external view returns (uint256 totalLiquidity, uint256 availableLiquidity, uint256 totalShares) {
        LiquidityPool storage pool = liquidityPools[_asset];
        return (pool.totalLiquidity, pool.availableLiquidity, pool.totalShares);
    }

    /**
     * @dev Get user's pool shares
     */
    function getUserPoolShares(address _user, address _asset) external view returns (uint256) {
        return userPoolShares[_user][_asset];
    }

    /**
     * @dev Get options expiring soon (within 24 hours)
     */
    function getExpiringOptions() external view returns (uint256[] memory) {
        uint256[] memory expiring = new uint256[](marketData.activeOptionsCount);
        uint256 count = 0;
        uint256 threshold = block.timestamp.add(24 hours);
        
        for (uint256 i = 0; i < optionCounter; i++) {
            if (options[i].state == OptionState.ACTIVE && options[i].expiry <= threshold) {
                expiring[count] = i;
                count++;
            }
        }
        
        // Resize array to actual count
        assembly {
            mstore(expiring, count)
        }
        
        return expiring;
    }

    /**
     * @dev Get top volume assets
     */
    function getTopVolumeAssets(uint256 _limit) external view returns (address[] memory, uint256[] memory) {
        // This would require additional sorting logic in production
        // Simplified implementation
        address[] memory assets = new address[](_limit);
        uint256[] memory volumes = new uint256[](_limit);
        
        // Return placeholder data - implement proper sorting in production
        return (assets, volumes);
    }

    /**
     * @dev Get user's insurance info
     */
    function getUserInsurance(address _user, uint256 _optionId) external view returns (Insurance memory) {
        return userInsurance[_user][_optionId];
    }

    // Admin functions

    /**
     * @dev Whitelist/blacklist asset for trading
     */
    function setAssetWhitelisted(address _asset, bool _whitelisted) external onlyOwner {
        whitelistedAssets[_asset] = _whitelisted;
        emit AssetWhitelisted(_asset, _whitelisted);
    }

    /**
     * @dev Update asset volatility
     */
    function updateAssetVolatility(address _asset, uint256 _volatility) external onlyAuthorizedPriceFeed {
        assetPrices[_asset].volatility = _volatility;
        emit VolatilityUpdated(_asset, _volatility);
    }

    /**
     * @dev Set liquidity incentive rate
     */
    function setLiquidityIncentiveRate(uint256 _rate) external onlyOwner {
        require(_rate <= 2000, "Rate cannot exceed 20%");
        liquidityIncentiveRate = _rate;
    }

    /**
     * @dev Toggle features
     */
    function toggleFeature(string calldata _feature, bool _enabled) external onlyOwner {
        bytes32 featureHash = keccak256(abi.encodePacked(_feature));
        
        if (featureHash == keccak256(abi.encodePacked("autoExercise"))) {
            autoExerciseEnabled = _enabled;
        } else if (featureHash == keccak256(abi.encodePacked("flashLoans"))) {
            flashLoansEnabled = _enabled;
        } else if (featureHash == keccak256(abi.encodePacked("insurance"))) {
            insuranceEnabled = _enabled;
        }
    }

    // Include all existing functions from the original contract...
    // (purchaseOption, exerciseOption, cancelOption, etc.)
        

   

   
    
       
        
            
        
           
        

        
                

       
   
       
        
       
       
   
    
        

    
