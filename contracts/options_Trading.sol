// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract AdvancedOptionsTradingPlatform is ReentrancyGuard, Ownable, Pausable, EIP712 {
    using SafeMath for uint256;
    using ECDSA for bytes32;

    // Existing enums (keeping all original)
    enum OptionType { CALL, PUT }
    enum OptionState { ACTIVE, EXPIRED, EXERCISED, CANCELLED }
    enum OrderType { BUY, SELL }
    enum OrderStatus { PENDING, FILLED, CANCELLED, PARTIAL }
    enum AlertType { PRICE_ABOVE, PRICE_BELOW, VOLATILITY_SPIKE, EXPIRY_WARNING }
    enum TournamentStatus { UPCOMING, ACTIVE, ENDED }
    enum InsuranceClaimStatus { PENDING, APPROVED, REJECTED, PAID }
    enum MarketPhase { PRE_MARKET, MARKET_OPEN, POST_MARKET, WEEKEND }
    enum YieldStrategy { CONSERVATIVE, MODERATE, AGGRESSIVE }
    enum VestingSchedule { LINEAR, CLIFF, EXPONENTIAL }
    enum GovernanceProposalType { PARAMETER_CHANGE, FEATURE_ADDITION, TREASURY_ALLOCATION, EMERGENCY_PAUSE }
    enum GovernanceStatus { PENDING, ACTIVE, SUCCEEDED, DEFEATED, EXECUTED }
    enum SocialSentiment { VERY_BEARISH, BEARISH, NEUTRAL, BULLISH, VERY_BULLISH }
    enum ComplianceLevel { BASIC, ENHANCED, INSTITUTIONAL }
    enum FlashLoanStatus { PENDING, EXECUTED, FAILED, LIQUIDATED }
    enum OracleType { CHAINLINK, UNI_V3_TWAP, CUSTOM, HYBRID }
    enum LiquidityTier { TIER_1, TIER_2, TIER_3, TIER_4 }
    enum SubscriptionTier { BASIC, PREMIUM, PROFESSIONAL, INSTITUTIONAL }
    enum AIModelType { SENTIMENT_ANALYSIS, PRICE_PREDICTION, VOLATILITY_FORECAST, RISK_ASSESSMENT }
    enum StakingRewardType { PLATFORM_TOKENS, OPTION_PREMIUMS, TRADING_FEES, GOVERNANCE_POWER }
    enum PortfolioRebalanceType { CONSERVATIVE, BALANCED, AGGRESSIVE, CUSTOM }
    enum CrossChainBridge { ETHEREUM, POLYGON, ARBITRUM, OPTIMISM, AVALANCHE }
    enum DeFiProtocol { AAVE, COMPOUND, UNISWAP, CURVE, YEARN }
    enum WeatherDerivativeType { TEMPERATURE, RAINFALL, WIND_SPEED, SNOW_DEPTH }

    // NEW ENUMS for additional functionality
    enum PricingModel { BLACK_SCHOLES, BINOMIAL, MONTE_CARLO, HESTON, LOCAL_VOLATILITY }
    enum SocialTradeType { COPY_TRADE, MIRROR_TRADE, SIGNAL_FOLLOW, PORTFOLIO_COPY }
    enum NFTOptionType { FLOOR_PRICE, TRAIT_BASED, COLLECTION_BASED, FRACTIONALIZED }
    enum AMMStrategy { CONSTANT_PRODUCT, CONSTANT_SUM, STABLE_SWAP, CONCENTRATED_LIQUIDITY }
    enum RiskLevel { VERY_LOW, LOW, MEDIUM, HIGH, VERY_HIGH }
    enum CreditRating { AAA, AA, A, BBB, BB, B, CCC, DEFAULT }
    enum MarketRegime { BULL, BEAR, SIDEWAYS, HIGH_VOLATILITY, LOW_VOLATILITY }
    enum OptionsStrategy { COVERED_CALL, PROTECTIVE_PUT, STRADDLE, STRANGLE, IRON_CONDOR, BUTTERFLY }
    enum LeverageType { FIXED, DYNAMIC, ADAPTIVE, RISK_PARITY }
    enum ComplianceFramework { MIFID_II, DODD_FRANK, BASEL_III, GDPR, KYC_AML }

    // Original structs (keeping all existing ones)
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
        bool hasBarrier;
        uint256 barrierPrice;
        bool isKnockedOut;
    }

    // NEW: Dynamic Pricing Engine with Multiple Models
    struct PricingEngine {
        uint256 engineId;
        PricingModel primaryModel;
        PricingModel[] secondaryModels;
        mapping(PricingModel => uint256) modelWeights;
        uint256 calibrationFrequency;
        uint256 lastCalibration;
        mapping(address => uint256) assetParameters;
        uint256 modelAccuracy;
        bool isActive;
        uint256 computationCost;
        mapping(uint256 => uint256) historicalPrices; // For model backtesting
    }

    // NEW: Social Trading Network
    struct SocialTrader {
        address trader;
        string username;
        string bio;
        uint256 followers;
        uint256 following;
        uint256 totalTrades;
        uint256 winRate;
        uint256 averageReturn;
        uint256 maxDrawdown;
        uint256 riskScore;
        uint256 socialRank;
        bool isVerified;
        uint256 copyTradeFee; // Fee percentage for copy trading
        mapping(address => bool) followers_map;
        mapping(SocialTradeType => bool) allowedTradeTypes;
        uint256 lastActiveTime;
    }

    struct CopyTrade {
        uint256 copyTradeId;
        address masterTrader;
        address copyTrader;
        SocialTradeType tradeType;
        uint256 allocationPercentage;
        uint256 maxSlippage;
        uint256 maxDrawdown;
        bool isActive;
        uint256 totalCopied;
        uint256 totalProfit;
        uint256 startTime;
        mapping(uint256 => bool) copiedTrades;
    }

    // NEW: NFT Options Market
    struct NFTOption {
        uint256 id;
        address nftContract;
        uint256 tokenId;
        NFTOptionType nftType;
        uint256 strikePrice; // Floor price or specific value
        uint256 premium;
        uint256 expiry;
        address creator;
        address buyer;
        bool isActive;
        bytes32 traitHash; // For trait-based options
        uint256 collectionFloorPrice;
        uint256 rarityScore;
        bool requiresPhysicalDelivery;
    }

    // NEW: Automated Market Maker for Options
    struct OptionsAMM {
        uint256 poolId;
        address asset;
        AMMStrategy strategy;
        uint256 totalLiquidity;
        uint256 k; // Constant product parameter
        mapping(uint256 => uint256) strikeLiquidity; // Strike price -> liquidity
        mapping(uint256 => uint256) expiryLiquidity; // Expiry -> liquidity
        uint256 feeRate;
        uint256 impermanentLossProtection;
        bool isActive;
        uint256 totalVolume;
        uint256 totalFees;
        mapping(address => uint256) liquidityProviders;
        uint256 minLiquidity;
        uint256 maxLiquidity;
    }

    // NEW: Advanced Risk Management System
    struct RiskManager {
        address user;
        RiskLevel maxRiskLevel;
        uint256 maxPositionSize;
        uint256 maxDailyLoss;
        uint256 maxPortfolioConcentration;
        uint256 varLimit; // Value at Risk limit
        uint256 stressTestResults;
        mapping(address => uint256) assetExposureLimits;
        mapping(OptionsStrategy => uint256) strategyLimits;
        bool autoLiquidationEnabled;
        uint256 marginCallThreshold;
        uint256 lastRiskAssessment;
        CreditRating creditRating;
    }

    // NEW: Market Making and Liquidity Provision
    struct MarketMaker {
        address maker;
        uint256 makerId;
        mapping(address => uint256) quotedSpreads; // Asset -> bid-ask spread
        mapping(address => uint256) inventoryLimits;
        mapping(address => uint256) currentInventory;
        uint256 totalQuotes;
        uint256 filledQuotes;
        uint256 totalPnL;
        bool isActive;
        uint256 minQuoteSize;
        uint256 maxQuoteSize;
        uint256 quotingFrequency;
        mapping(uint256 => uint256) strikeQuotes; // Strike -> quote count
    }

    // NEW: Regulatory Compliance and Reporting
    struct ComplianceModule {
        address entity;
        ComplianceFramework framework;
        mapping(string => bool) requiredDocuments;
        mapping(string => uint256) documentTimestamps;
        uint256 lastAudit;
        uint256 complianceScore;
        bool isCompliant;
        mapping(address => bool) authorizedPersons;
        uint256 reportingFrequency;
        mapping(uint256 => bytes32) reportHashes;
        uint256 penaltyScore;
        bool suspendedTrading;
    }

    // NEW: Exotic Options and Structured Products
    struct ExoticOption {
        uint256 id;
        address creator;
        string productName;
        OptionsStrategy strategy;
        address[] underlyingAssets;
        uint256[] weights;
        uint256[] strikes;
        uint256[] expiries;
        uint256 premium;
        uint256 maxPayout;
        bool isKnockOut;
        bool isKnockIn;
        uint256[] barriers;
        bytes32 payoffFormula; // Hash of payoff calculation
        bool isPath_dependent;
        uint256 observationFrequency;
    }

    // NEW: Volatility Trading and Swaps
    struct VolatilitySwap {
        uint256 swapId;
        address payer;
        address receiver;
        address underlyingAsset;
        uint256 notional;
        uint256 strikeVolatility;
        uint256 startDate;
        uint256 endDate;
        uint256 observationFrequency;
        uint256[] realizedVolatility;
        bool isVarianceSwap;
        uint256 cap; // Volatility cap
        uint256 floor; // Volatility floor
        bool isSettled;
        uint256 settlementAmount;
    }

    // NEW: Algorithmic Trading Strategies
    struct TradingBot {
        uint256 botId;
        address owner;
        string strategyName;
        bytes32 strategyHash;
        mapping(string => uint256) parameters;
        uint256 allocatedCapital;
        uint256 currentPnL;
        uint256 maxDrawdown;
        uint256 sharpeRatio;
        bool isActive;
        uint256 executionFrequency;
        uint256 lastExecution;
        mapping(address => bool) allowedAssets;
        uint256 riskBudget;
        LeverageType leverageType;
        uint256 maxLeverage;
    }

    // NEW: Credit Default Swaps for DeFi Protocols
    struct CreditDefaultSwap {
        uint256 cdsId;
        address protectionBuyer;
        address protectionSeller;
        address referenceEntity; // DeFi protocol address
        uint256 notional;
        uint256 premium; // Annual premium
        uint256 startDate;
        uint256 maturityDate;
        bool isActive;
        bool hasDefaulted;
        uint256[] premiumPayments;
        uint256 recoveryRate;
        bytes32[] creditEvents; // Hash of credit event descriptions
    }

    // NEW: Options Market Intelligence and Analytics
    struct MarketIntelligence {
        address asset;
        uint256 timestamp;
        uint256 openInterest;
        uint256 volume;
        uint256 putCallRatio;
        uint256 maxPain; // Max pain price
        uint256 impliedVolatility;
        uint256 historicalVolatility;
        mapping(uint256 => uint256) strikePriceDistribution;
        mapping(uint256 => uint256) expiryDistribution;
        SocialSentiment sentiment;
        MarketRegime regime;
        uint256 flowDirection; // Net flow: positive = bullish, negative = bearish
        uint256 unusualActivity; // Unusual options activity indicator
    }

    // Enhanced mappings for all new features
    mapping(uint256 => PricingEngine) public pricingEngines;
    mapping(address => SocialTrader) public socialTraders;
    mapping(uint256 => CopyTrade) public copyTrades;
    mapping(uint256 => NFTOption) public nftOptions;
    mapping(uint256 => OptionsAMM) public optionsAMMs;
    mapping(address => RiskManager) public riskManagers;
    mapping(address => MarketMaker) public marketMakers;
    mapping(address => ComplianceModule) public complianceModules;
    mapping(uint256 => ExoticOption) public exoticOptions;
    mapping(uint256 => VolatilitySwap) public volatilitySwaps;
    mapping(uint256 => TradingBot) public tradingBots;
    mapping(uint256 => CreditDefaultSwap) public creditDefaultSwaps;
    mapping(address => MarketIntelligence) public marketIntelligence;

    // New counters
    uint256 public pricingEngineCounter;
    uint256 public copyTradeCounter;
    uint256 public nftOptionCounter;
    uint256 public ammPoolCounter;
    uint256 public exoticOptionCounter;
    uint256 public volatilitySwapCounter;
    uint256 public tradingBotCounter;
    uint256 public cdsCounter;

    // Platform parameters
    uint256 public socialTradingFeeRate = 500; // 5%
    uint256 public nftOptionFeeRate = 250; // 2.5%
    uint256 public ammFeeRate = 30; // 0.3%
    uint256 public maxLeverage = 1000; // 10x
    uint256 public minCollateralRatio = 15000; // 150%

    // Events for new functionality
    event PricingEngineCalibrated(uint256 indexed engineId, PricingModel model, uint256 accuracy);
    event SocialTraderRegistered(address indexed trader, string username);
    event CopyTradeStarted(uint256 indexed copyTradeId, address master, address follower);
    event NFTOptionCreated(uint256 indexed optionId, address nftContract, uint256 tokenId);
    event AMMPoolCreated(uint256 indexed poolId, address asset, AMMStrategy strategy);
    event RiskLimitExceeded(address indexed user, RiskLevel level, uint256 exposure);
    event MarketMakerQuote(address indexed maker, address asset, uint256 bidPrice, uint256 askPrice);
    event ComplianceViolation(address indexed entity, ComplianceFramework framework, string violation);
    event ExoticOptionCreated(uint256 indexed optionId, string productName, OptionsStrategy strategy);
    event VolatilitySwapSettled(uint256 indexed swapId, uint256 realizedVol, uint256 settlement);
    event TradingBotExecuted(uint256 indexed botId, string strategy, uint256 pnl);
    event CreditEventTriggered(uint256 indexed cdsId, address entity, bytes32 eventHash);
    event UnusualActivityDetected(address indexed asset, uint256 volume, uint256 threshold);

    constructor(address _governanceToken) Ownable(msg.sender) EIP712("AdvancedOptionsTradingPlatform", "5.0") {
        // Constructor implementation
    }

    // NEW FUNCTIONS START HERE

    /**
     * Create advanced pricing engine with multiple models
     */
    function createPricingEngine(
        PricingModel _primaryModel,
        PricingModel[] calldata _secondaryModels,
        uint256[] calldata _modelWeights,
        uint256 _calibrationFrequency
    ) external onlyOwner {
        require(_secondaryModels.length == _modelWeights.length, "Array length mismatch");
        
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < _modelWeights.length; i++) {
            totalWeight = totalWeight.add(_modelWeights[i]);
        }
        require(totalWeight <= 10000, "Total weight cannot exceed 100%");
        
        uint256 engineId = pricingEngineCounter++;
        
        PricingEngine storage engine = pricingEngines[engineId];
        engine.engineId = engineId;
        engine.primaryModel = _primaryModel;
        engine.secondaryModels = _secondaryModels;
        engine.calibrationFrequency = _calibrationFrequency;
        engine.lastCalibration = block.timestamp;
        engine.isActive = true;
        
        for (uint256 i = 0; i < _secondaryModels.length; i++) {
            engine.modelWeights[_secondaryModels[i]] = _modelWeights[i];
        }
        
        emit PricingEngineCalibrated(engineId, _primaryModel, 0);
    }

    /**
     * Register as social trader
     */
    function registerSocialTrader(
        string calldata _username,
        string calldata _bio,
        uint256 _copyTradeFee,
        SocialTradeType[] calldata _allowedTypes
    ) external {
        require(_copyTradeFee <= 2000, "Copy trade fee too high"); // Max 20%
        
        SocialTrader storage trader = socialTraders[msg.sender];
        trader.trader = msg.sender;
        trader.username = _username;
        trader.bio = _bio;
        trader.copyTradeFee = _copyTradeFee;
        trader.riskScore = 500; // Medium risk initially
        trader.lastActiveTime = block.timestamp;
        
        for (uint256 i = 0; i < _allowedTypes.length; i++) {
            trader.allowedTradeTypes[_allowedTypes[i]] = true;
        }
        
        emit SocialTraderRegistered(msg.sender, _username);
    }

    /**
     * Start copy trading
     */
    function startCopyTrading(
        address _masterTrader,
        SocialTradeType _tradeType,
        uint256 _allocationPercentage,
        uint256 _maxSlippage,
        uint256 _maxDrawdown
    ) external nonReentrant {
        require(_allocationPercentage <= 10000, "Allocation cannot exceed 100%");
        require(_maxSlippage <= 1000, "Max slippage too high"); // Max 10%
        require(socialTraders[_masterTrader].trader != address(0), "Master trader not registered");
        require(socialTraders[_masterTrader].allowedTradeTypes[_tradeType], "Trade type not allowed");
        
        uint256 copyTradeId = copyTradeCounter++;
        
        CopyTrade storage copyTrade = copyTrades[copyTradeId];
        copyTrade.copyTradeId = copyTradeId;
        copyTrade.masterTrader = _masterTrader;
        copyTrade.copyTrader = msg.sender;
        copyTrade.tradeType = _tradeType;
        copyTrade.allocationPercentage = _allocationPercentage;
        copyTrade.maxSlippage = _maxSlippage;
        copyTrade.maxDrawdown = _maxDrawdown;
        copyTrade.isActive = true;
        copyTrade.startTime = block.timestamp;
        
        // Add follower to master trader
        socialTraders[_masterTrader].followers = socialTraders[_masterTrader].followers.add(1);
        socialTraders[_masterTrader].followers_map[msg.sender] = true;
        
        emit CopyTradeStarted(copyTradeId, _masterTrader, msg.sender);
    }

    /**
     * Create NFT option
     */
    function createNFTOption(
        address _nftContract,
        uint256 _tokenId,
        NFTOptionType _nftType,
        uint256 _strikePrice,
        uint256 _premium,
        uint256 _expiry,
        bytes32 _traitHash
    ) external payable nonReentrant {
        require(msg.value >= nftOptionFeeRate * _premium / 10000, "Insufficient fee");
        require(_expiry > block.timestamp, "Expiry must be in future");
        
        uint256 optionId = nftOptionCounter++;
        
        NFTOption storage nftOption = nftOptions[optionId];
        nftOption.id = optionId;
        nftOption.nftContract = _nftContract;
        nftOption.tokenId = _tokenId;
        nftOption.nftType = _nftType;
        nftOption.strikePrice = _strikePrice;
        nftOption.premium = _premium;
        nftOption.expiry = _expiry;
        nftOption.creator = msg.sender;
        nftOption.traitHash = _traitHash;
        nftOption.isActive = true;
        
        emit NFTOptionCreated(optionId, _nftContract, _tokenId);
    }

    /**
     * Create Options AMM Pool
     */
    function createOptionsAMM(
        address _asset,
        AMMStrategy _strategy,
        uint256 _initialLiquidity,
        uint256 _feeRate
    ) external payable nonReentrant {
        require(msg.value >= _initialLiquidity, "Insufficient initial liquidity");
        require(_feeRate <= 1000, "Fee rate too high"); // Max 10%
        
        uint256 poolId = ammPoolCounter++;
        
        OptionsAMM storage amm = optionsAMMs[poolId];
        amm.poolId = poolId;
        amm.asset = _asset;
        amm.strategy = _strategy;
        amm.totalLiquidity = _initialLiquidity;
        amm.feeRate = _feeRate;
        amm.isActive = true;
        amm.minLiquidity = _initialLiquidity.div(10); // 10% of initial
        amm.maxLiquidity = _initialLiquidity.mul(100); // 100x initial
        amm.liquidityProviders[msg.sender] = _initialLiquidity;
        
        // Set k parameter for constant product
        if (_strategy == AMMStrategy.CONSTANT_PRODUCT) {
            amm.k = _initialLiquidity.mul(_initialLiquidity);
        }
        
        emit AMMPoolCreated(poolId, _asset, _strategy);
    }

    /**
     * Setup advanced risk management
     */
    function setupRiskManager(
        RiskLevel _maxRiskLevel,
        uint256 _maxPositionSize,
        uint256 _maxDailyLoss,
        uint256 _maxPortfolioConcentration,
        uint256 _varLimit,
        bool _autoLiquidationEnabled
    ) external {
        RiskManager storage riskMgr = riskManagers[msg.sender];
        riskMgr.user = msg.sender;
        riskMgr.maxRiskLevel = _maxRiskLevel;
        riskMgr.maxPositionSize = _maxPositionSize;
        riskMgr.maxDailyLoss = _maxDailyLoss;
        riskMgr.maxPortfolioConcentration = _maxPortfolioConcentration;
        riskMgr.varLimit = _varLimit;
        riskMgr.autoLiquidationEnabled = _autoLiquidationEnabled;
        riskMgr.marginCallThreshold = 12000; // 120%
        riskMgr.lastRiskAssessment = block.timestamp;
        riskMgr.creditRating = CreditRating.BBB; // Default rating
    }

    /**
     * Register as market maker
     */
    function registerMarketMaker(
        mapping(address => uint256) calldata _quotedSpreads,
        mapping(address => uint256) calldata _inventoryLimits,
        uint256 _minQuoteSize,
        uint256 _maxQuoteSize
    ) external {
        MarketMaker storage maker = marketMakers[msg.sender];
        maker.maker = msg.sender;
        maker.makerId = uint256(uint160(msg.sender)); // Use address as ID
        maker.isActive = true;
        maker.minQuoteSize = _minQuoteSize;
        maker.maxQuoteSize = _maxQuoteSize;
        maker.quotingFrequency = 300; // 5 minutes default
    }

    /**
     * Submit market maker quote
     */
    function submitMarketMakerQuote(
        address _asset,
        uint256 _bidPrice,
        uint256 _askPrice,
        uint256 _size
    ) external {
        MarketMaker storage maker = marketMakers[msg.sender];
        require(maker.isActive, "Market maker not active");
        require(_size >= maker.minQuoteSize && _size <= maker.maxQuoteSize, "Invalid quote size");
        require(_askPrice > _bidPrice, "Invalid spread");
        
        maker.totalQuotes = maker.totalQuotes.add(1);
        maker.quotedSpreads[_asset] = _askPrice.sub(_bidPrice);
        
        emit MarketMakerQuote(msg.sender, _asset, _bidPrice, _askPrice);
    }

    /**
     * Setup compliance module
     */
    function setupCompliance(
        ComplianceFramework _framework,
        string[] calldata _requiredDocuments
    ) external {
        ComplianceModule storage compliance = complianceModules[msg.sender];
        compliance.entity = msg.sender;
        compliance.framework = _framework;
        compliance.lastAudit = block.timestamp;
        compliance.complianceScore = 750; // Default score
        compliance.reportingFrequency = 2592000; // 30 days
        
        for (uint256 i = 0; i < _requiredDocuments.length; i++) {
            compliance.requiredDocuments[_requiredDocuments[i]] = true;
        }
    }

    /**
     * Create exotic option with complex payoff
     */
    function createExoticOption(
        string calldata _productName,
        OptionsStrategy _strategy,
        address[] calldata _underlyingAssets,
        uint256[] calldata _weights,
        uint256[] calldata _strikes,
        uint256[] calldata _expiries,
        uint256 _premium,
        bytes32 _payoffFormula
    ) external payable nonReentrant {
        require(_underlyingAssets.length == _weights.length, "Array length mismatch");
        require(msg.value >= _premium, "Insufficient premium");
        
        uint256 optionId = exoticOptionCounter++;
        
        ExoticOption storage exotic = exoticOptions[optionId];
        exotic.id = optionId;
        exotic.creator = msg.sender;
        exotic.productName = _productName;
        exotic.strategy = _strategy;
        exotic.underlyingAssets = _underlyingAssets;
        exotic.weights = _weights;
        exotic.strikes = _strikes;
        exotic.expiries = _expiries;
        exotic.premium = _premium;
        exotic.payoffFormula = _payoffFormula;
        exotic.observationFrequency = 86400; // Daily observations
        
        emit ExoticOptionCreated(optionId, _productName, _strategy);
    }

    /**
     * Create volatility swap
     */
    function createVolatilitySwap(
        address _counterparty,
        address _underlyingAsset,
        uint256 _notional,
        uint256 _strikeVolatility,
        uint256 _startDate,
        uint256 _endDate,
        uint256 _cap,
        uint256 _floor,
        bool _isVarianceSwap
    ) external nonReentrant {
        require(_startDate > block.timestamp, "Start date must be in future");
        require(_endDate > _startDate, "End date must be after start date");
        require(_cap > _strikeVolatility && _strikeVolatility > _floor, "Invalid vol levels");
        
        uint256 swapId = volatilitySwapCounter++;
        
        VolatilitySwap storage volSwap = volatilitySwaps[swapId];
        volSwap.swapId = swapId;
        volSwap.payer = msg.sender;
        volSwap.receiver = _counterparty;
        volSwap.underlyingAsset = _underlyingAsset;
        volSwap.notional = _notional;
        volSwap.strikeVolatility = _strikeVolatility;
        volSwap.startDate = _startDate;
        volSwap.endDate = _endDate;
        volSwap.cap = _cap;
        volSwap.floor = _floor;
        volSwap.isVarianceSwap = _isVarianceSwap;
        volSwap.observationFrequency = 86400; // Daily observations
    }

    /**
     * Create automated trading bot
     */
    function createTradingBot(
        string calldata _strategyName,
        bytes32 _strategyHash,
        uint256 _allocatedCapital,
        uint256 _executionFrequency,
        address[] calldata _allowedAssets,
        uint256 _riskBudget,
        LeverageType _leverageType,
        uint256 _maxLeverage
    ) external payable nonReentrant {
        require(msg.value >= _allocatedCapital, "Insufficient capital");
        require(_maxLeverage <= maxLeverage, "Leverage too high");
        
        uint256 botId = tradingBotCounter++;
        
        TradingBot storage bot = tradingBots[botId];
        bot.botId = botId;
        bot.owner = msg.sender;
        bot.strategyName = _strategyName;
        bot.strategyHash = _strategyHash;
        bot.allocatedCapital = _allocatedCapital;
        bot.executionFrequency = _executionFrequency;
        bot.riskBudget = _riskBudget;
        bot.leverageType = _lever
