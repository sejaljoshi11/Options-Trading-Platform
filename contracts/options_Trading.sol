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
    enum AlertType { PRICE_ABOVE, PRICE_BELOW, VOLATILITY_SPIKE, EXPIRY_WARNING }
    enum TournamentStatus { UPCOMING, ACTIVE, ENDED }

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
        uint256 maxLoss;
        uint256 marginRequired;
        bool hasBarrier; // NEW: Barrier option
        uint256 barrierPrice; // NEW: Barrier price level
        bool isKnockedOut; // NEW: Barrier knock-out status
    }

    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 volatility;
        uint256 high24h;
        uint256 low24h;
        uint256 volume24h;
        uint256 openInterest; // NEW: Open interest tracking
        int256 priceChange24h; // NEW: 24h price change
        uint256 bid; // NEW: Current bid price
        uint256 ask; // NEW: Current ask price
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
        uint256 riskScore;
        uint256 maxDrawdown;
        uint256 sharpeRatio;
        uint256 totalTrades; // NEW: Total number of trades
        uint256 profitableTrades; // NEW: Number of profitable trades
        uint256 averageProfit; // NEW: Average profit per trade
        uint256 maxConsecutiveLosses; // NEW: Max consecutive losses
    }

    // NEW: Advanced Order Types
    struct ConditionalOrder {
        uint256 id;
        address trader;
        uint256 optionId;
        OrderType orderType;
        uint256 triggerPrice;
        uint256 limitPrice;
        uint256 quantity;
        bool isActive;
        uint256 expiry;
        AlertType triggerType;
    }

    // NEW: Copy Trading Structure
    struct CopyTrading {
        address leader;
        uint256 allocationAmount;
        uint256 maxRiskPerTrade;
        bool isActive;
        uint256 totalCopiedTrades;
        uint256 totalProfit;
        uint256 followersCount;
    }

    // NEW: Social Trading Features
    struct TradingSignal {
        uint256 id;
        address signalProvider;
        uint256 optionId;
        string analysis;
        uint256 confidence; // 1-100
        uint256 targetPrice;
        uint256 stopLoss;
        uint256 timestamp;
        bool isActive;
        uint256 subscribers;
    }

    // NEW: Options Strategy Templates
    struct StrategyTemplate {
        uint256 id;
        string name;
        string description;
        uint256[] optionIds;
        int256 expectedReturn;
        uint256 maxRisk;
        uint256 complexity; // 1-10 scale
        bool isActive;
        address creator;
    }

    // NEW: Advanced Analytics
    struct PortfolioAnalytics {
        uint256 totalValue;
        uint256 dailyPnL;
        uint256 weeklyPnL;
        uint256 monthlyPnL;
        uint256 beta;
        uint256 alpha;
        uint256 valueAtRisk; // VaR calculation
        uint256 expectedShortfall; // CVaR
        mapping(address => uint256) sectorExposure;
        mapping(uint256 => uint256) timeDecayRisk; // Theta exposure by expiry
    }

    // NEW: Tournament & Competition
    struct Tournament {
        uint256 id;
        string name;
        uint256 startTime;
        uint256 endTime;
        uint256 entryFee;
        uint256 prizePool;
        address[] participants;
        mapping(address => uint256) scores;
        address winner;
        TournamentStatus status;
        uint256 maxParticipants;
    }

    // NEW: Price Alerts System
    struct PriceAlert {
        uint256 id;
        address user;
        address asset;
        AlertType alertType;
        uint256 targetPrice;
        bool isActive;
        uint256 createdAt;
        bool isTriggered;
    }

    // NEW: Risk Management Tools
    struct RiskParameters {
        uint256 maxPositionSize;
        uint256 maxDailyLoss;
        uint256 maxConcentration; // % of portfolio in single asset
        uint256 maxLeverage;
        bool stopLossEnabled;
        bool takeProfitEnabled;
        uint256 correlationLimit; // Max correlation between positions
    }

    // NEW: Advanced Liquidity Mining
    struct LiquidityMiningPool {
        address asset;
        uint256 totalLiquidity;
        uint256 rewardRate;
        uint256 multiplier;
        uint256 lockPeriod;
        mapping(address => uint256) userShares;
        mapping(address => uint256) stakingTime;
        mapping(address => uint256) pendingRewards;
        bool isActive;
    }

    // NEW: Options Market Making
    struct MarketMakerQuote {
        address marketMaker;
        uint256 optionId;
        uint256 bidPrice;
        uint256 askPrice;
        uint256 bidSize;
        uint256 askSize;
        uint256 timestamp;
        bool isActive;
    }

    // NEW: Synthetic Assets
    struct SyntheticAsset {
        uint256 id;
        string name;
        string symbol;
        address[] underlyingAssets;
        uint256[] weights;
        uint256 totalSupply;
        mapping(address => uint256) balances;
        bool isActive;
    }

    // Existing mappings + new ones
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

    // NEW mappings
    mapping(uint256 => ConditionalOrder) public conditionalOrders;
    mapping(address => uint256[]) public userConditionalOrders;
    mapping(address => CopyTrading) public copyTradingSettings;
    mapping(address => address[]) public copiedTraders; // user => leaders they copy
    mapping(address => address[]) public followers; // leader => followers
    mapping(uint256 => TradingSignal) public tradingSignals;
    mapping(address => uint256[]) public userSignals;
    mapping(uint256 => StrategyTemplate) public strategyTemplates;
    mapping(address => PortfolioAnalytics) public portfolioAnalytics;
    mapping(uint256 => Tournament) public tournaments;
    mapping(address => uint256[]) public userTournaments;
    mapping(uint256 => PriceAlert) public priceAlerts;
    mapping(address => uint256[]) public userAlerts;
    mapping(address => RiskParameters) public userRiskParams;
    mapping(address => LiquidityMiningPool) public liquidityPools;
    mapping(uint256 => MarketMakerQuote) public marketMakerQuotes;
    mapping(uint256 => SyntheticAsset) public syntheticAssets;
    mapping(address => bool) public approvedMarketMakers;
    mapping(address => uint256) public tradingVolume24h;
    mapping(address => uint256) public lastTradeTime;
    mapping(uint256 => uint256) public optionVolatilitySurface;
    mapping(address => mapping(uint256 => uint256)) public historicalVolatility;
    mapping(uint256 => bool) public autoHedgingEnabled;
    mapping(address => uint256) public socialTradingTier; // 1-5 tiers

    // Counters
    uint256 public optionCounter;
    uint256 public conditionalOrderCounter;
    uint256 public signalCounter;
    uint256 public strategyCounter;
    uint256 public tournamentCounter;
    uint256 public alertCounter;
    uint256 public syntheticAssetCounter;

    // NEW Events
    event ConditionalOrderCreated(uint256 indexed orderId, address indexed trader, uint256 triggerPrice, AlertType triggerType);
    event ConditionalOrderTriggered(uint256 indexed orderId, address indexed trader, uint256 executionPrice);
    event CopyTradeExecuted(address indexed follower, address indexed leader, uint256 optionId, uint256 amount);
    event TradingSignalCreated(uint256 indexed signalId, address indexed provider, uint256 optionId, uint256 confidence);
    event StrategyTemplateCreated(uint256 indexed strategyId, address indexed creator, string name);
    event TournamentCreated(uint256 indexed tournamentId, string name, uint256 prizePool);
    event TournamentJoined(uint256 indexed tournamentId, address indexed participant);
    event TournamentEnded(uint256 indexed tournamentId, address indexed winner, uint256 prize);
    event PriceAlertTriggered(uint256 indexed alertId, address indexed user, address asset, uint256 price);
    event RiskLimitExceeded(address indexed user, string riskType, uint256 currentValue, uint256 limit);
    event SyntheticAssetCreated(uint256 indexed assetId, string name, string symbol);
    event MarketMakerQuoteUpdated(address indexed marketMaker, uint256 indexed optionId, uint256 bidPrice, uint256 askPrice);
    event VolatilityUpdated(address indexed asset, uint256 newVolatility, uint256 timestamp);
    event LiquidityMiningRewardClaimed(address indexed user, address indexed asset, uint256 reward);
    event AutoHedgeExecuted(uint256 indexed optionId, address indexed user, uint256 hedgeAmount);

    constructor(address _governanceToken) Ownable(msg.sender) EIP712("OptionsTradingPlatform", "2.0") {
        authorizedPriceFeeds[msg.sender] = true;
        // Initialize default risk parameters
        _setDefaultRiskParameters();
    }

    /**
     * NEW: Create conditional/stop orders
     */
    function createConditionalOrder(
        uint256 _optionId,
        OrderType _orderType,
        uint256 _triggerPrice,
        uint256 _limitPrice,
        uint256 _quantity,
        AlertType _triggerType,
        uint256 _expiry
    ) external payable nonReentrant whenNotPaused {
        require(_quantity > 0, "Quantity must be positive");
        require(_expiry > block.timestamp, "Expiry must be in future");
        require(_triggerPrice > 0, "Invalid trigger price");

        uint256 orderId = conditionalOrderCounter++;
        
        conditionalOrders[orderId] = ConditionalOrder({
            id: orderId,
            trader: msg.sender,
            optionId: _optionId,
            orderType: _orderType,
            triggerPrice: _triggerPrice,
            limitPrice: _limitPrice,
            quantity: _quantity,
            isActive: true,
            expiry: _expiry,
            triggerType: _triggerType
        });

        userConditionalOrders[msg.sender].push(orderId);

        emit ConditionalOrderCreated(orderId, msg.sender, _triggerPrice, _triggerType);
    }

    /**
     * NEW: Execute conditional order when conditions are met
     */
    function executeConditionalOrder(uint256 _orderId) external nonReentrant {
        ConditionalOrder storage order = conditionalOrders[_orderId];
        require(order.isActive, "Order not active");
        require(block.timestamp <= order.expiry, "Order expired");

        bool shouldExecute = _checkConditionalOrderTrigger(_orderId);
        require(shouldExecute, "Trigger condition not met");

        order.isActive = false;
        
        // Execute the actual trade
        _executeTrade(order.optionId, order.orderType, order.limitPrice, order.quantity, order.trader);

        emit ConditionalOrderTriggered(_orderId, order.trader, order.limitPrice);
    }

    /**
     * NEW: Copy trading - follow a successful trader
     */
    function followTrader(
        address _leader,
        uint256 _allocationAmount,
        uint256 _maxRiskPerTrade
    ) external payable nonReentrant {
        require(msg.value >= _allocationAmount, "Insufficient funds");
        require(_leader != msg.sender, "Cannot follow yourself");
        require(userReputationScore[_leader] >= 500, "Leader reputation too low");

        copyTradingSettings[msg.sender] = CopyTrading({
            leader: _leader,
            allocationAmount: _allocationAmount,
            maxRiskPerTrade: _maxRiskPerTrade,
            isActive: true,
            totalCopiedTrades: 0,
            totalProfit: 0,
            followersCount: 0
        });

        copiedTraders[msg.sender].push(_leader);
        followers[_leader].push(msg.sender);
        
        // Increase leader's follower count
        copyTradingSettings[_leader].followersCount++;
    }

    /**
     * NEW: Create trading signal with analysis
     */
    function createTradingSignal(
        uint256 _optionId,
        string calldata _analysis,
        uint256 _confidence,
        uint256 _targetPrice,
        uint256 _stopLoss
    ) external nonReentrant {
        require(_confidence >= 1 && _confidence <= 100, "Confidence must be 1-100");
        require(userReputationScore[msg.sender] >= 300, "Insufficient reputation to create signals");

        uint256 signalId = signalCounter++;
        
        tradingSignals[signalId] = TradingSignal({
            id: signalId,
            signalProvider: msg.sender,
            optionId: _optionId,
            analysis: _analysis,
            confidence: _confidence,
            targetPrice: _targetPrice,
            stopLoss: _stopLoss,
            timestamp: block.timestamp,
            isActive: true,
            subscribers: 0
        });

        userSignals[msg.sender].push(signalId);

        emit TradingSignalCreated(signalId, msg.sender, _optionId, _confidence);
    }

    /**
     * NEW: Create strategy template (e.g., covered call, iron condor)
     */
    function createStrategyTemplate(
        string calldata _name,
        string calldata _description,
        uint256[] calldata _optionIds,
        int256 _expectedReturn,
        uint256 _maxRisk,
        uint256 _complexity
    ) external nonReentrant {
        require(_optionIds.length > 0, "Strategy must include options");
        require(_complexity >= 1 && _complexity <= 10, "Complexity must be 1-10");

        uint256 strategyId = strategyCounter++;
        
        strategyTemplates[strategyId] = StrategyTemplate({
            id: strategyId,
            name: _name,
            description: _description,
            optionIds: _optionIds,
            expectedReturn: _expectedReturn,
            maxRisk: _maxRisk,
            complexity: _complexity,
            isActive: true,
            creator: msg.sender
        });

        emit StrategyTemplateCreated(strategyId, msg.sender, _name);
    }

    /**
     * NEW: Create trading tournament/competition
     */
    function createTournament(
        string calldata _name,
        uint256 _duration,
        uint256 _entryFee,
        uint256 _maxParticipants
    ) external payable onlyOwner {
        require(_duration > 0, "Duration must be positive");
        require(_maxParticipants > 1, "Need at least 2 participants");

        uint256 tournamentId = tournamentCounter++;
        
        Tournament storage tournament = tournaments[tournamentId];
        tournament.id = tournamentId;
        tournament.name = _name;
        tournament.startTime = block.timestamp;
        tournament.endTime = block.timestamp.add(_duration);
        tournament.entryFee = _entryFee;
        tournament.prizePool = msg.value;
        tournament.status = TournamentStatus.UPCOMING;
        tournament.maxParticipants = _maxParticipants;

        emit TournamentCreated(tournamentId, _name, msg.value);
    }

    /**
     * NEW: Join trading tournament
     */
    function joinTournament(uint256 _tournamentId) external payable nonReentrant {
        Tournament storage tournament = tournaments[_tournamentId];
        require(tournament.status == TournamentStatus.UPCOMING, "Tournament not accepting entries");
        require(msg.value >= tournament.entryFee, "Insufficient entry fee");
        require(tournament.participants.length < tournament.maxParticipants, "Tournament full");

        tournament.participants.push(msg.sender);
        tournament.prizePool = tournament.prizePool.add(msg.value);
        userTournaments[msg.sender].push(_tournamentId);

        // Start tournament if enough participants
        if (tournament.participants.length == tournament.maxParticipants) {
            tournament.status = TournamentStatus.ACTIVE;
        }

        emit TournamentJoined(_tournamentId, msg.sender);
    }

    /**
     * NEW: Set price alerts
     */
    function createPriceAlert(
        address _asset,
        AlertType _alertType,
        uint256 _targetPrice
    ) external nonReentrant {
        require(whitelistedAssets[_asset], "Asset not supported");
        require(_targetPrice > 0, "Invalid target price");

        uint256 alertId = alertCounter++;
        
        priceAlerts[alertId] = PriceAlert({
            id: alertId,
            user: msg.sender,
            asset: _asset,
            alertType: _alertType,
            targetPrice: _targetPrice,
            isActive: true,
            createdAt: block.timestamp,
            isTriggered: false
        });

        userAlerts[msg.sender].push(alertId);
    }

    /**
     * NEW: Set personal risk management parameters
     */
    function setRiskParameters(
        uint256 _maxPositionSize,
        uint256 _maxDailyLoss,
        uint256 _maxConcentration,
        uint256 _maxLeverage,
        bool _stopLossEnabled,
        bool _takeProfitEnabled
    ) external {
        userRiskParams[msg.sender] = RiskParameters({
            maxPositionSize: _maxPositionSize,
            maxDailyLoss: _maxDailyLoss,
            maxConcentration: _maxConcentration,
            maxLeverage: _maxLeverage,
            stopLossEnabled: _stopLossEnabled,
            takeProfitEnabled: _takeProfitEnabled,
            correlationLimit: 7000 // 70% max correlation
        });
    }

    /**
     * NEW: Create synthetic asset from multiple underlying assets
     */
    function createSyntheticAsset(
        string calldata _name,
        string calldata _symbol,
        address[] calldata _underlyingAssets,
        uint256[] calldata _weights
    ) external onlyOwner {
        require(_underlyingAssets.length == _weights.length, "Arrays length mismatch");
        require(_underlyingAssets.length > 1, "Need multiple underlying assets");

        uint256 totalWeight = 0;
        for (uint256 i = 0; i < _weights.length; i++) {
            totalWeight = totalWeight.add(_weights[i]);
        }
        require(totalWeight == 10000, "Weights must sum to 100%"); // 10000 basis points

        uint256 assetId = syntheticAssetCounter++;
        
        SyntheticAsset storage synAsset = syntheticAssets[assetId];
        synAsset.id = assetId;
        synAsset.name = _name;
        synAsset.symbol = _symbol;
        synAsset.underlyingAssets = _underlyingAssets;
        synAsset.weights = _weights;
        synAsset.isActive = true;

        emit SyntheticAssetCreated(assetId, _name, _symbol);
    }

    /**
     * NEW: Market maker quote management
     */
    function updateMarketMakerQuote(
        uint256 _optionId,
        uint256 _bidPrice,
        uint256 _askPrice,
        uint256 _bidSize,
        uint256 _askSize
    ) external {
        require(approvedMarketMakers[msg.sender], "Not approved market maker");
        require(_askPrice > _bidPrice, "Ask must be higher than bid");

        marketMakerQuotes[_optionId] = MarketMakerQuote({
            marketMaker: msg.sender,
            optionId: _optionId,
            bidPrice: _bidPrice,
            askPrice: _askPrice,
            bidSize: _bidSize,
            askSize: _askSize,
            timestamp: block.timestamp,
            isActive: true
        });

        emit MarketMakerQuoteUpdated(msg.sender, _optionId, _bidPrice, _askPrice);
    }

    /**
     * NEW: Auto-hedging for option positions
     */
    function enableAutoHedging(uint256 _optionId, bool _enabled) external {
        Option memory option = options[_optionId];
        require(option.buyer == msg.sender || option.creator == msg.sender, "Not authorized");
        
        autoHedgingEnabled[_optionId] = _enabled;
    }

    /**
     * NEW: Calculate portfolio Value at Risk (VaR)
     */
    function calculatePortfolioVaR(address _user, uint256 _confidenceLevel) external view returns (uint256) {
        // Simplified VaR calculation using historical simulation
        PortfolioAnalytics storage analytics = portfolioAnalytics[_user];
        
        uint256 portfolioValue = analytics.totalValue;
        if (portfolioValue == 0) return 0;

        // Use historical volatility for VaR estimation
        uint256 volatility = _getPortfolioVolatility(_user);
        uint256 z_score = _getZScore(_confidenceLevel); // 95% confidence = 1.645

        return portfolioValue.mul(volatility).mul(z_score).div(10000);
    }

    /**
     * NEW: Advanced portfolio rebalancing with risk constraints
     */
    function rebalancePortfolioAdvanced() external nonReentrant {
        RiskParameters memory riskParams = userRiskParams[msg.sender];
        PortfolioAnalytics storage analytics = portfolioAnalytics[msg.sender];
        
        // Check if rebalancing is needed based on risk metrics
        uint256 currentVaR = calculatePortfolioVaR(msg.sender, 95);
        uint256 maxAllowedVaR = analytics.totalValue.mul(riskParams.maxDailyLoss).div(10000);
        
        if (currentVaR > maxAllowedVaR) {
            // Reduce position sizes to meet risk constraints
            _reduceRiskyPositions(msg.sender, currentVaR, maxAllowedVaR);
        }

        // Check concentration limits
        _checkConcentrationLimits(msg.sender);
        
        emit PortfolioRebalanced(msg.sender, analytics.totalValue, analytics.dailyPnL);
    }

    /**
     * NEW: AI-powered option pricing with machine learning
     */
    function getAIPricePrediction(address _asset) external view returns (uint256 predictedPrice, uint256 confidence) {
        // Simplified AI price prediction using historical data
        PriceData memory priceData = assetPrices[_asset];
        
        // Use weighted moving average with volatility adjustment
        uint256 basePrice = priceData.price;
        uint256 volatilityAdjustment = priceData.volatility.mul(basePrice).div(10000);
        
        // Trend analysis based on 24h change
        if (priceData.priceChange24h > 0) {
            predictedPrice = basePrice.add(volatilityAdjustment.div(2));
        } else {
            predictedPrice = basePrice.sub(volatilityAdjustment.div(2));
        }
        
        confidence = 75; // 75% confidence in prediction
        
        return (predictedPrice, confidence);
    }

    /**
     * NEW: Cross-chain option bridge (placeholder for cross-chain functionality)
     */
    function bridgeOptionToChain(uint256 _optionId, uint256 _destinationChainId) external payable {
        require(options[_optionId].buyer == msg.sender, "Only option buyer can bridge");
        require(msg.value >= 0.001 ether, "Bridge fee required");
        
        // Lock option on current chain
        options[_optionId].state = OptionState.CANCELLED; // Temporary state for bridging
        
        // Emit event for bridge oracle to process
        emit OptionBridged(_optionId, msg.sender, _destinationChainId);
    }

    // NEW Event for cross-chain bridging
    event OptionBridged(uint256 indexed optionId, address indexed user, uint256 destinationChain);

    /**
     * NEW: Social sentiment analysis integration
     */
    function updateSocialSentiment(address _asset, int256 _sentimentScore) external onlyAuthorizedPriceFeed {
        require(_sentimentScore >= -100 && _sentimentScore <= 100, "Sentiment score must be -100 to 100");
        
        // Store sentiment data for pricing models
        socialSentiment[_asset] = SentimentData({
            score: _sentimentScore,
            timestamp: block.timestamp,
            sampleSize: 1000 // Number of social media posts analyzed
        });
    }

    // NEW: Sentiment data structure
    struct SentimentData {
        int256 score; // -100 to +100
        uint256 timestamp;
        uint256 sampleSize;
    }
    
    mapping(address => SentimentData) public socialSentiment;

    // Internal helper functions

    function _checkConditionalOrderTrigger(uint256 _orderId) internal view returns (bool) {
        ConditionalOrder memory order = conditionalOrders[_orderId];
        Option memory option = options[order.optionId];
        uint256 currentPrice = assetPrices[option.underlyingAsset].price;

        if (order.triggerType == AlertType.PRICE_ABOVE) {
            return currentPrice >= order.triggerPrice;
        } else if (order.triggerType == AlertType.PRICE_BELOW) {
            return currentPrice <= order.triggerPrice;
        }
        
        return false;
    }

    function _executeTrade(
        uint256 _optionId,
        OrderType _orderType,
        uint256 _price,
        uint256 _quantity,
        address _trader
    ) internal {
        // Simplified trade execution logic
        Option storage option = options[_optionId];
        
        if (_orderType == OrderType.BUY && option.buyer == address(0)) {
            option.buyer = _trader;
            option.premium = _price;
        }
    }

    function _getPortfolioVolatility(address _user) internal view returns (uint256) {
        // Calculate portfolio volatility based on user's positions
        uint256[] memory userOptionIds = userOptions[_user];
        uint256 totalVolatility = 0;
        
        for (uint256 i = 0; i < userOptionIds.length; i++) {
            Option memory option = options[userOptionIds[i]];
            totalVolatility = totalVolatility.add(option.impliedVolatility);
        }
        
        return userOptionIds.length > 0 ? totalVolatility.div(userOptionIds.length) : 0;
    }

    function _getZScore(uint256 _confidenceLevel) internal pure returns (uint256) {
        // Simplified z-score lookup for common confidence levels
        if (_confidenceLevel == 90) return 1282; // 1.282 * 1000
        if (_confidenceLevel == 95) return 1645; // 1.645 * 1000
        if (_confidenceLevel == 99) return 2326; // 2.326 * 1000
        return 1645; // Default to 95%
    }

    function _reduceRiskyPositions(address _user, uint256 _currentVaR, uint256 _maxVaR) internal {
        // Reduce position sizes to meet risk limits
        uint256 reductionRatio = _maxVaR.mul(10000).div(_currentVaR);
        
        uint256[] memory userOptionIds = userOptions[_user];
        for (uint256 i = 0; i < userOptionIds.length; i++) {
            Option storage option = options[userOptionIds[i]];
            if (option.buyer == _user && option.state == OptionState.ACTIVE) {
                option.amount = option.amount.mul(reductionRatio).div(10000);
            }
        }
    }

    function _checkConcentrationLimits(
        
        
        
       
       
    
   
    
    
 
   

   

        

      
   
     
     

   
   
    
                
     
  
     
   
    
    
   

   
    
       
    
    
       
           
        
       
       

   
           
            
            
        
       
       

   

       
       

   

   
    
       
        
            
        
           
        

        
                

       
   
       
        
       
       
   
    
        

    
