// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract OptionsTradingPlatform is ReentrancyGuard, Ownable, Pausable, EIP712 {
    using SafeMath for uint256;
    using ECDSA for bytes32;

    enum OptionType { CALL, PUT }
    enum OptionState { ACTIVE, EXPIRED, EXERCISED, CANCELLED }
    enum OrderType { BUY, SELL }
    enum OrderStatus { PENDING, FILLED, CANCELLED, PARTIAL }

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
        uint256 impliedVolatility;
        bool isSpread;
        uint256 spreadStrike2;
        uint256 maxLoss; // New: Maximum loss for risk management
        uint256 marginRequired; // New: Margin requirement
    }

    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 volatility;
        uint256 high24h; // New: 24h high
        uint256 low24h;  // New: 24h low
        uint256 volume24h; // New: 24h volume
    }

    struct UserStats {
        uint256 totalOptionsCreated;
        uint256 totalOptionsBought;
        uint256 totalOptionsExercised;
        uint256 totalPremiumEarned;
        uint256 totalPremiumPaid;
        uint256 totalProfitFromExercise;
        uint256 winRate;
        uint256 averageHoldTime;
        uint256 riskScore; // New: Risk assessment score
        uint256 maxDrawdown; // New: Maximum drawdown
        uint256 sharpeRatio; // New: Risk-adjusted returns
    }

    struct MarketData {
        uint256 totalVolume;
        uint256 totalOptionsCreated;
        uint256 totalOptionsExercised;
        uint256 activeOptionsCount;
        uint256 totalTradingFees;
        uint256 averageImpliedVolatility; // New: Market-wide IV
        uint256 putCallRatio; // New: Put/Call ratio
    }

    struct LiquidityPool {
        uint256 totalLiquidity;
        uint256 availableLiquidity;
        mapping(address => uint256) userShares;
        uint256 totalShares;
        uint256 feeRate;
        uint256 utilizationRate; // New: Pool utilization
        uint256 apy; // New: Annual percentage yield
    }

    struct FlashLoan {
        uint256 amount;
        uint256 fee;
        address borrower;
        bool active;
        uint256 timestamp; // New: Loan timestamp
    }

    struct Insurance {
        uint256 premium;
        uint256 coverage;
        uint256 expiry;
        bool isActive;
        uint256 claimAmount; // New: Amount claimed
    }

    // NEW: Order Book Structure
    struct Order {
        uint256 id;
        address trader;
        uint256 optionId;
        OrderType orderType;
        uint256 price;
        uint256 quantity;
        uint256 filled;
        OrderStatus status;
        uint256 timestamp;
        uint256 expiry;
        bool isLimitOrder;
    }

    // NEW: Staking Structure
    struct StakeInfo {
        uint256 amount;
        uint256 timestamp;
        uint256 rewards;
        uint256 lockPeriod;
        bool isLocked;
    }

    // NEW: Portfolio Structure
    struct Portfolio {
        uint256[] activeOptions;
        uint256 totalValue;
        uint256 pnl;
        uint256 marginUsed;
        uint256 availableMargin;
        mapping(address => uint256) assetExposure;
    }

    // NEW: Governance Structure
    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        mapping(address => bool) hasVoted;
    }

    // NEW: Yield Farming Structure
    struct YieldFarm {
        address token;
        uint256 rewardRate;
        uint256 totalStaked;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) rewards;
        mapping(address => uint256) balances;
    }

    // Existing mappings
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
    mapping(address => LiquidityPool) public liquidityPools;
    mapping(address => mapping(address => uint256)) public userPoolShares;
    mapping(uint256 => FlashLoan) public flashLoans;
    mapping(address => mapping(uint256 => Insurance)) public userInsurance;
    mapping(address => uint256[]) public priceHistory;
    mapping(uint256 => uint256[]) public optionChain;
    mapping(address => bool) public whitelistedAssets;
    mapping(address => uint256) public assetTradingVolume;
    mapping(address => uint256) public lastActivityTime;
    mapping(uint256 => bool) public autoExerciseEnabled;
    mapping(address => uint256) public referralRewards;
    mapping(address => address) public referrals;

    // NEW mappings
    mapping(uint256 => Order) public orders;
    mapping(address => uint256[]) public userOrders;
    mapping(uint256 => uint256[]) public optionOrders; // optionId => orderIds
    mapping(address => StakeInfo) public stakes;
    mapping(address => Portfolio) public portfolios;
    mapping(uint256 => Proposal) public proposals;
    mapping(address => uint256) public votingPower;
    mapping(address => YieldFarm) public yieldFarms;
    mapping(address => bool) public isMarketMaker;
    mapping(address => uint256) public creditLimits;
    mapping(address => uint256) public marginBalances;
    mapping(uint256 => uint256) public optionGreeks; // optionId => packed Greeks (delta, gamma, theta, vega)
    mapping(address => mapping(uint256 => bool)) public userVotedProposal;
    mapping(address => uint256[]) public watchlists;
    mapping(address => bool) public isPremiumUser;
    mapping(address => uint256) public tradingFeeDiscounts;
    mapping(uint256 => bytes32) public optionSignatures; // For signed orders
    mapping(address => uint256) public lastHealthCheck;

    // Counters
    uint256 public optionCounter;
    uint256 public flashLoanCounter;
    uint256 public orderCounter; // NEW
    uint256 public proposalCounter; // NEW

    // Constants
    uint256 public constant EXERCISE_WINDOW = 1 hours;
    uint256 public constant PRICE_VALIDITY_DURATION = 1 hours;
    uint256 public platformFee = 100; // 1% = 100 basis points
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_REPUTATION_SCORE = 0;
    uint256 public constant MAX_REPUTATION_SCORE = 1000;
    uint256 public constant FLASH_LOAN_FEE = 30; // 0.3%
    uint256 public constant INSURANCE_RATE = 200; // 2%
    uint256 public constant REFERRAL_BONUS = 50; // 0.5%
    uint256 public liquidityIncentiveRate = 500; // 5% APY for LP tokens
    
    // NEW constants
    uint256 public constant MIN_MARGIN_RATIO = 150; // 150% minimum margin
    uint256 public constant LIQUIDATION_THRESHOLD = 110; // 110% liquidation threshold
    uint256 public constant GOVERNANCE_QUORUM = 1000; // 10% quorum requirement
    uint256 public constant PROPOSAL_DURATION = 7 days;
    uint256 public constant STAKING_LOCK_PERIOD = 30 days;
    uint256 public constant MAX_LEVERAGE = 10; // 10x maximum leverage
    uint256 public constant MARKET_MAKER_DISCOUNT = 50; // 0.5% discount for market makers

    // State variables
    MarketData public marketData;
    bool public biddingEnabled = true;
    bool public reputationSystemEnabled = true;
    bool public autoExerciseEnabled = true;
    bool public flashLoansEnabled = true;
    bool public insuranceEnabled = true;
    bool public marginTradingEnabled = true; // NEW
    bool public governanceEnabled = true; // NEW
    bool public stakingEnabled = true; // NEW
    uint256 public maxOptionDuration = 365 days;
    uint256 public minOptionDuration = 1 hours;
    uint256 public totalStakedTokens; // NEW
    address public governanceToken; // NEW
    uint256 public protocolRevenue; // NEW

    // NEW events
    event OrderPlaced(uint256 indexed orderId, address indexed trader, uint256 indexed optionId, OrderType orderType, uint256 price, uint256 quantity);
    event OrderFilled(uint256 indexed orderId, address indexed trader, uint256 filledAmount, uint256 price);
    event OrderCancelled(uint256 indexed orderId, address indexed trader);
    event StakeDeposited(address indexed user, uint256 amount, uint256 lockPeriod);
    event StakeWithdrawn(address indexed user, uint256 amount, uint256 rewards);
    event MarginCall(address indexed user, uint256 marginRequired, uint256 currentMargin);
    event Liquidation(address indexed user, uint256 liquidatedAmount, address liquidator);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 votes);
    event ProposalExecuted(uint256 indexed proposalId);
    event GreeksUpdated(uint256 indexed optionId, uint256 delta, uint256 gamma, uint256 theta, uint256 vega);
    event PortfolioRebalanced(address indexed user, uint256 newValue, uint256 pnl);
    event YieldClaimed(address indexed user, address indexed farm, uint256 reward);
    event CreditLimitUpdated(address indexed user, uint256 newLimit);
    event PremiumStatusUpdated(address indexed user, bool isPremium);

    // Existing events
    event LiquidityProvided(address indexed provider, address indexed asset, uint256 amount, uint256 shares);
    event LiquidityWithdrawn(address indexed provider, address indexed asset, uint256 amount, uint256 shares);
    event FlashLoanExecuted(uint256 indexed loanId, address indexed borrower, uint256 amount, uint256 fee);
    event InsurancePurchased(address indexed user, uint256 indexed optionId, uint256 premium, uint256 coverage);
    event AutoExerciseExecuted(uint256 indexed optionId, address indexed buyer, uint256 profit);
    event VolatilityUpdated(address indexed asset, uint256 newVolatility);
    event SpreadOptionCreated(uint256 indexed optionId, uint256 strike1, uint256 strike2);
    event ReferralRewardPaid(address indexed referrer, address indexed referee, uint256 amount);
    event AssetWhitelisted(address indexed asset, bool status);
    event OptionCreated(uint256 indexed optionId, address indexed creator, address indexed underlyingAsset, uint256 strikePrice, uint256 premium, uint256 expiry, OptionType optionType, bool isAmerican);
    event OptionPurchased(uint256 indexed optionId, address indexed buyer, uint256 premium);
    event OptionExercised(uint256 indexed optionId, address indexed buyer, uint256 profit);
    event OptionCancelled(uint256 indexed optionId, address indexed creator);
    event OptionExpired(uint256 indexed optionId);
    event PriceUpdated(address indexed asset, uint256 price, uint256 timestamp);
    event CollateralDeposited(address indexed user, address indexed asset, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed asset, uint256 amount);
    event BidPlaced(uint256 indexed optionId, address indexed bidder, uint256 bidAmount);
    event BidWithdrawn(uint256 indexed optionId, address indexed bidder, uint256 bidAmount);
    event ReputationUpdated(address indexed user, uint256 newScore, string reason);

    // Modifiers (existing ones plus new ones)
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

    modifier onlyWhitelistedAsset(address _asset) {
        require(whitelistedAssets[_asset] || msg.sender == owner(), "Asset not whitelisted");
        _;
    }

    modifier flashLoansOnly() {
        require(flashLoansEnabled, "Flash loans disabled");
        _;
    }

    // NEW modifiers
    modifier onlyMarketMaker() {
        require(isMarketMaker[msg.sender], "Only market makers allowed");
        _;
    }

    modifier marginEnabled() {
        require(marginTradingEnabled, "Margin trading disabled");
        _;
    }

    modifier sufficientMargin(address _user, uint256 _amount) {
        require(getAvailableMargin(_user) >= _amount, "Insufficient margin");
        _;
    }

    modifier notLiquidated(address _user) {
        require(!isLiquidatable(_user), "User position liquidated");
        _;
    }

    modifier onlyPremiumUser() {
        require(isPremiumUser[msg.sender], "Premium feature required");
        _;
    }

    constructor(address _governanceToken) Ownable(msg.sender) EIP712("OptionsTradingPlatform", "1") {
        authorizedPriceFeeds[msg.sender] = true;
        governanceToken = _governanceToken;
    }

    /**
     * NEW: Place limit/market order in order book
     */
    function placeOrder(
        uint256 _optionId,
        OrderType _orderType,
        uint256 _price,
        uint256 _quantity,
        bool _isLimitOrder,
        uint256 _expiry
    ) external payable nonReentrant whenNotPaused optionExists(_optionId) {
        require(_quantity > 0, "Quantity must be greater than 0");
        require(_expiry > block.timestamp, "Order expiry must be in future");
        
        if (_isLimitOrder) {
            require(_price > 0, "Limit price must be greater than 0");
        }

        uint256 orderId = orderCounter++;
        
        orders[orderId] = Order({
            id: orderId,
            trader: msg.sender,
            optionId: _optionId,
            orderType: _orderType,
            price: _price,
            quantity: _quantity,
            filled: 0,
            status: OrderStatus.PENDING,
            timestamp: block.timestamp,
            expiry: _expiry,
            isLimitOrder: _isLimitOrder
        });

        userOrders[msg.sender].push(orderId);
        optionOrders[_optionId].push(orderId);

        // Try to match order immediately
        if (!_isLimitOrder) {
            _matchMarketOrder(orderId);
        } else {
            _matchLimitOrder(orderId);
        }

        emit OrderPlaced(orderId, msg.sender, _optionId, _orderType, _price, _quantity);
    }

    /**
     * NEW: Cancel order
     */
    function cancelOrder(uint256 _orderId) external nonReentrant {
        Order storage order = orders[_orderId];
        require(order.trader == msg.sender, "Only order creator can cancel");
        require(order.status == OrderStatus.PENDING, "Order not cancellable");

        order.status = OrderStatus.CANCELLED;
        
        // Refund any locked funds if necessary
        if (order.orderType == OrderType.BUY) {
            uint256 refundAmount = order.quantity.sub(order.filled).mul(order.price);
            if (refundAmount > 0) {
                (bool success, ) = msg.sender.call{value: refundAmount}("");
                require(success, "Refund failed");
            }
        }

        emit OrderCancelled(_orderId, msg.sender);
    }

    /**
     * NEW: Stake tokens for governance and rewards
     */
    function stakeTokens(uint256 _amount, uint256 _lockPeriod) external nonReentrant {
        require(stakingEnabled, "Staking disabled");
        require(_amount > 0, "Amount must be greater than 0");
        require(_lockPeriod >= STAKING_LOCK_PERIOD, "Lock period too short");

        IERC20(governanceToken).transferFrom(msg.sender, address(this), _amount);

        StakeInfo storage stake = stakes[msg.sender];
        
        // Calculate rewards for existing stake
        if (stake.amount > 0) {
            uint256 rewards = _calculateStakeRewards(msg.sender);
            stake.rewards = stake.rewards.add(rewards);
        }

        stake.amount = stake.amount.add(_amount);
        stake.timestamp = block.timestamp;
        stake.lockPeriod = _lockPeriod;
        stake.isLocked = true;

        totalStakedTokens = totalStakedTokens.add(_amount);
        votingPower[msg.sender] = votingPower[msg.sender].add(_amount);

        emit StakeDeposited(msg.sender, _amount, _lockPeriod);
    }

    /**
     * NEW: Unstake tokens and claim rewards
     */
    function unstakeTokens(uint256 _amount) external nonReentrant {
        StakeInfo storage stake = stakes[msg.sender];
        require(stake.amount >= _amount, "Insufficient staked amount");
        
        if (stake.isLocked) {
            require(block.timestamp >= stake.timestamp.add(stake.lockPeriod), "Tokens still locked");
        }

        uint256 rewards = _calculateStakeRewards(msg.sender);
        stake.rewards = stake.rewards.add(rewards);

        stake.amount = stake.amount.sub(_amount);
        totalStakedTokens = totalStakedTokens.sub(_amount);
        votingPower[msg.sender] = votingPower[msg.sender].sub(_amount);

        // Transfer staked tokens back
        IERC20(governanceToken).transfer(msg.sender, _amount);
        
        // Transfer rewards
        if (stake.rewards > 0) {
            uint256 rewardAmount = stake.rewards;
            stake.rewards = 0;
            (bool success, ) = msg.sender.call{value: rewardAmount}("");
            require(success, "Reward transfer failed");
        }

        emit StakeWithdrawn(msg.sender, _amount, rewards);
    }

    /**
     * NEW: Create governance proposal
     */
    function createProposal(string calldata _description) external returns (uint256) {
        require(governanceEnabled, "Governance disabled");
        require(votingPower[msg.sender] >= 100, "Insufficient voting power to create proposal");

        uint256 proposalId = proposalCounter++;
        
        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.description = _description;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp.add(PROPOSAL_DURATION);
        proposal.executed = false;

        emit ProposalCreated(proposalId, msg.sender, _description);
        return proposalId;
    }

    /**
     * NEW: Vote on governance proposal
     */
    function vote(uint256 _proposalId, bool _support) external {
        require(governanceEnabled, "Governance disabled");
        require(_proposalId < proposalCounter, "Proposal does not exist");
        require(votingPower[msg.sender] > 0, "No voting power");

        Proposal storage proposal = proposals[_proposalId];
        require(block.timestamp >= proposal.startTime, "Voting not started");
        require(block.timestamp <= proposal.endTime, "Voting ended");
        require(!userVotedProposal[msg.sender][_proposalId], "Already voted");

        uint256 votes = votingPower[msg.sender];
        userVotedProposal[msg.sender][_proposalId] = true;

        if (_support) {
            proposal.votesFor = proposal.votesFor.add(votes);
        } else {
            proposal.votesAgainst = proposal.votesAgainst.add(votes);
        }

        emit VoteCast(_proposalId, msg.sender, _support, votes);
    }

    /**
     * NEW: Enable margin trading with leverage
     */
    function enableMarginTrading(address _user, uint256 _creditLimit) external onlyOwner {
        creditLimits[_user] = _creditLimit;
        marginBalances[_user] = 0;
    }

    /**
     * NEW: Deposit margin
     */
    function depositMargin() external payable nonReentrant marginEnabled {
        require(msg.value > 0, "Must deposit positive amount");
        marginBalances[msg.sender] = marginBalances[msg.sender].add(msg.value);
        _updatePortfolio(msg.sender);
    }

    /**
     * NEW: Withdraw margin
     */
    function withdrawMargin(uint256 _amount) external nonReentrant marginEnabled notLiquidated(msg.sender) {
        require(_amount > 0, "Amount must be greater than 0");
        require(getAvailableMargin(msg.sender) >= _amount, "Insufficient available margin");

        marginBalances[msg.sender] = marginBalances[msg.sender].sub(_amount);
        _updatePortfolio(msg.sender);

        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Withdrawal failed");
    }

    /**
     * NEW: Liquidate undercollateralized position
     */
    function liquidatePosition(address _user) external nonReentrant {
        require(isLiquidatable(_user), "Position not liquidatable");

        Portfolio storage portfolio = portfolios[_user];
        uint256 liquidationAmount = portfolio.marginUsed.mul(110).div(100); // 110% of margin used

        // Close all positions
        for (uint256 i = 0; i < portfolio.activeOptions.length; i++) {
            uint256 optionId = portfolio.activeOptions[i];
            Option storage option = options[optionId];
            
            if (option.state == OptionState.ACTIVE) {
                option.state = OptionState.CANCELLED;
                marketData.activeOptionsCount--;
            }
        }

        // Transfer liquidation reward to liquidator (5% of liquidated amount)
        uint256 reward = liquidationAmount.mul(500).div(BASIS_POINTS);
        (bool success, ) = msg.sender.call{value: reward}("");
        require(success, "Liquidation reward transfer failed");

        // Reset user's portfolio
        portfolio.totalValue = 0;
        portfolio.marginUsed = 0;
        delete portfolio.activeOptions;

        emit Liquidation(_user, liquidationAmount, msg.sender);
    }

    /**
     * NEW: Add asset to watchlist
     */
    function addToWatchlist(address _asset) external onlyWhitelistedAsset(_asset) {
        watchlists[msg.sender].push(_asset);
    }

    /**
     * NEW: Remove asset from watchlist
     */
    function removeFromWatchlist(address _asset, uint256 _index) external {
        require(_index < watchlists[msg.sender].length, "Invalid index");
        require(watchlists[msg.sender][_index] == _asset, "Asset not at index");

        watchlists[msg.sender][_index] = watchlists[msg.sender][watchlists[msg.sender].length - 1];
        watchlists[msg.sender].pop();
    }

    /**
     * NEW: Calculate and update option Greeks
     */
    function updateOptionGreeks(uint256 _optionId) external optionExists(_optionId) validPrice(options[_optionId].underlyingAsset) {
        Option memory option = options[_optionId];
        uint256 currentPrice = assetPrices[option.underlyingAsset].price;
        uint256 timeToExpiry = option.expiry > block.timestamp ? option.expiry.sub(block.timestamp) : 0;
        uint256 volatility = assetPrices[option.underlyingAsset].volatility;

        // Calculate Greeks (simplified calculations)
        uint256 delta = _calculateDelta(currentPrice, option.strikePrice, timeToExpiry, volatility, option.optionType);
        uint256 gamma = _calculateGamma(currentPrice, option.strikePrice, timeToExpiry, volatility);
        uint256 theta = _calculateTheta(currentPrice, option.strikePrice, timeToExpiry, volatility);
        uint256 vega = _calculateVega(currentPrice, option.strikePrice, timeToExpiry, volatility);

        // Pack Greeks into single uint256 for gas efficiency
        optionGreeks[_optionId] = (delta << 192) | (gamma << 128) | (theta << 64) | vega;

        emit GreeksUpdated(_optionId, delta, gamma, theta, vega);
    }

    /**
     * NEW: Set up yield farming for liquidity providers
     */
    function createYieldFarm(address _token, uint256 _rewardRate) external onlyOwner {
        YieldFarm storage farm = yieldFarms[_token];
        farm.token = _token;
        farm.rewardRate = _rewardRate;
        farm.lastUpdateTime = block.timestamp;
    }

    /**
     * NEW: Stake in yield farm
     */
    function stakeInFarm(address _token, uint256 _amount) external nonReentrant {
        require(yieldFarms[_token].token != address(0), "Farm does not exist");
        
        YieldFarm storage farm = yieldFarms[_token];
        _updateFarmRewards(_token, msg.sender);

        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        farm.balances[msg.sender] = farm.balances[msg.sender].add(_amount);
        farm.totalStaked = farm.totalStaked.add(_amount);
    }

    /**
     * NEW: Claim yield farming rewards
     */
    function claimFarmRewards(address _token) external nonReentrant {
        YieldFarm storage farm = yieldFarms[_token];
        _updateFarmRewards(_token, msg.sender);

        uint256 reward = farm.rewards[msg.sender];
        if (reward > 0) {
            farm.rewards[msg.sender] = 0;
            (bool success, ) = msg.sender.call{value: reward}("");
            require(success, "Reward transfer failed");
            
            emit YieldClaimed(msg.sender, _token, reward);
        }
    }

    /**
     * NEW: Upgrade to premium user
     */
    function upgradeToPremium() external payable {
        require(msg.value >= 1 ether, "Insufficient payment for premium upgrade");
        isPremiumUser[msg.sender] = true;
        tradingFeeDiscounts[msg.sender] = 5000; // 50% discount
        protocolRevenue = protocolRevenue.add(msg.value);
        
        emit PremiumStatusUpdated(msg.sender, true);
    }

    /**
     * NEW: Automated portfolio rebalancing
     */
    function rebalancePortfolio() external nonReentrant {
        _updatePortfolio(msg.sender);
        
        Portfolio storage portfolio = portfolios[msg.sender];
        
        // Simple rebalancing logic - close losing positions if portfolio risk is too high
        if (portfolio.marginUsed > portfolio.availableMargin.mul(2)) {
            for (uint256 i = 0; i < portfolio.activeOptions.length; i++) {
                uint256 optionId = portfolio.activeOptions[i];
                Option storage option = options[optionId];
                
                if (option.state == OptionState.ACTIVE && option.buyer == msg.sender) {
                    uint256 currentPrice = assetPrices[option.underlyingAsset].price;
                    uint256 currentValue = calculateOptionValue(option, currentPrice);
                    
                    if (currentValue < option.premium.mul(80).div(100)) { // 20% loss
                        // Close position
                        option.state = OptionState.CANCELLED;
                        market
        
        

   
    
    
   

   
    
       
    
    
       
           
        
       
       

   
           
            
            
        
       
       

   

       
       

   

   
    
       
        
            
        
           
        

        
                

       
   
       
        
       
       
   
    
        

    
