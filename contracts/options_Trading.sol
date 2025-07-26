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

    // NEW ENUMS for added functionality
    enum DynamicHedgeType { DELTA_NEUTRAL, GAMMA_NEUTRAL, VEGA_NEUTRAL, THETA_NEUTRAL, RHO_NEUTRAL }
    enum PortfolioInsuranceType { STOP_LOSS, PROTECTIVE_PUT, CPPI, OBPI }
    enum ArbitrageType { STATISTICAL, TRIANGULAR, CALENDAR_SPREAD, VOLATILITY }
    enum LiquidityMiningTier { BRONZE, SILVER, GOLD, PLATINUM, DIAMOND }
    enum FlashLoanType { ARBITRAGE, LIQUIDATION, REFINANCING, SELF_LIQUIDATION }
    enum CommodityType { GOLD, OIL, WHEAT, CORN, COFFEE, NATURAL_GAS }
    enum EconomicIndicator { GDP, INFLATION, UNEMPLOYMENT, INTEREST_RATE, VIX }

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

    // NEW: Dynamic Hedging System
    struct DynamicHedge {
        uint256 hedgeId;
        address portfolio;
        DynamicHedgeType hedgeType;
        uint256 targetRatio; // Target hedge ratio (basis points)
        uint256 currentRatio;
        uint256 rebalanceThreshold; // Trigger rebalance when ratio deviates by this much
        uint256 lastRebalance;
        uint256 rebalanceFrequency;
        uint256 hedgingCost;
        address[] hedgingInstruments;
        uint256[] hedgeWeights;
        bool isActive;
        uint256 totalPnL;
        mapping(address => uint256) instrumentAllocations;
    }

    // NEW: Portfolio Insurance System
    struct PortfolioInsurance {
        uint256 insuranceId;
        address insuredPortfolio;
        PortfolioInsuranceType insuranceType;
        uint256 floorValue; // Minimum portfolio value to maintain
        uint256 multiplier; // CPPI multiplier
        uint256 cushion; // Current cushion above floor
        uint256 premiumPaid;
        uint256 maxDrawdown;
        uint256 startTime;
        uint256 duration;
        bool isActive;
        uint256 totalClaims;
        mapping(uint256 => uint256) valueHistory; // Time => portfolio value
    }

    // NEW: Arbitrage Opportunities Scanner
    struct ArbitrageOpportunity {
        uint256 arbId;
        ArbitrageType arbType;
        address[] assets;
        uint256[] prices;
        uint256 expectedProfit;
        uint256 requiredCapital;
        uint256 riskScore;
        uint256 timeWindow; // How long the opportunity lasts
        uint256 discoveredAt;
        bool isExecuted;
        address executor;
        uint256 actualProfit;
        mapping(string => uint256) executionSteps; // Step name => execution time
    }

    // NEW: Liquidity Mining Program
    struct LiquidityMining {
        address provider;
        LiquidityMiningTier tier;
        uint256 stakedAmount;
        uint256 stakingStart;
        uint256 lockupPeriod;
        uint256 rewardRate; // Rewards per second
        uint256 accumulatedRewards;
        uint256 lastClaimTime;
        uint256 multiplier; // Tier-based multiplier
        bool isActive;
        mapping(address => uint256) poolAllocations; // Pool address => staked amount
        uint256 totalVolumeGenerated;
        uint256 bonusRewards;
    }

    // NEW: Advanced Flash Loan System
    struct FlashLoanRequest {
        uint256 loanId;
        address borrower;
        address asset;
        uint256 amount;
        FlashLoanType loanType;
        uint256 fee;
        uint256 executionGas;
        bytes executionData;
        bool isExecuted;
        bool isRepaid;
        uint256 timestamp;
        uint256 profitGenerated;
        string strategy; // Human readable strategy description
    }

    // NEW: Commodity Options Market
    struct CommodityOption {
        uint256 id;
        CommodityType commodity;
        uint256 contractSize; // Standard contract size (e.g., 100 oz gold)
        uint256 strikePrice;
        uint256 premium;
        uint256 expiry;
        OptionType optionType;
        address creator;
        address buyer;
        bool physicalDelivery; // True if requires physical delivery
        string deliveryLocation;
        uint256 storageFeesPerDay;
        bool isActive;
        uint256 qualityGrade; // Commodity quality specifications
    }

    // NEW: Economic Derivatives
    struct EconomicDerivative {
        uint256 id;
        EconomicIndicator indicator;
        uint256 strikeValue; // Strike value for the economic indicator
        uint256 premium;
        uint256 expiry;
        OptionType optionType;
        address creator;
        address buyer;
        bool isSettled;
        uint256 settlementValue;
        string dataSource; // e.g., "Federal Reserve", "Bureau of Labor Statistics"
        uint256 settlementDelay; // Days after expiry to settle
    }

    // NEW: Cross-Asset Correlation Engine
    struct CorrelationEngine {
        mapping(bytes32 => int256) correlationMatrix; // hash(asset1, asset2) => correlation
        mapping(address => uint256[]) priceHistory;
        uint256 lookbackPeriod; // Days to look back for correlation calculation
        uint256 lastUpdate;
        uint256 updateFrequency;
        mapping(address => mapping(address => uint256)) volatilityAdjustedCorrelation;
        bool isActive;
    }

    // NEW: Options Greeks Calculator
    struct GreeksCalculator {
        mapping(uint256 => int256) delta; // Option ID => Delta
        mapping(uint256 => uint256) gamma; // Option ID => Gamma
        mapping(uint256 => int256) theta; // Option ID => Theta (time decay)
        mapping(uint256 => uint256) vega; // Option ID => Vega (volatility sensitivity)
        mapping(uint256 => int256) rho; // Option ID => Rho (interest rate sensitivity)
        uint256 lastCalculation;
        uint256 calculationFrequency;
        mapping(uint256 => uint256) impliedVolSurface; // Strike => IV
    }

    // NEW: Multi-Asset Basket Options
    struct BasketOption {
        uint256 id;
        address[] underlyingAssets;
        uint256[] weights; // Basis points (10000 = 100%)
        uint256 strikePrice;
        uint256 premium;
        uint256 expiry;
        OptionType optionType;
        address creator;
        address buyer;
        bool isActive;
        uint256 correlationAdjustment; // Adjustment for asset correlations
        mapping(address => uint256) assetPricesAtCreation;
        uint256 basketValue; // Current basket value
    }

    // Enhanced mappings for all new features
    mapping(uint256 => DynamicHedge) public dynamicHedges;
    mapping(uint256 => PortfolioInsurance) public portfolioInsurances;
    mapping(uint256 => ArbitrageOpportunity) public arbitrageOpportunities;
    mapping(address => LiquidityMining) public liquidityMining;
    mapping(uint256 => FlashLoanRequest) public flashLoanRequests;
    mapping(uint256 => CommodityOption) public commodityOptions;
    mapping(uint256 => EconomicDerivative) public economicDerivatives;
    mapping(uint256 => BasketOption) public basketOptions;

    // System components
    CorrelationEngine public correlationEngine;
    GreeksCalculator public greeksCalculator;

    // New counters
    uint256 public dynamicHedgeCounter;
    uint256 public portfolioInsuranceCounter;
    uint256 public arbitrageCounter;
    uint256 public flashLoanCounter;
    uint256 public commodityOptionCounter;
    uint256 public economicDerivativeCounter;
    uint256 public basketOptionCounter;

    // Platform parameters for new features
    uint256 public hedgingFeeRate = 50; // 0.5%
    uint256 public insurancePremiumRate = 200; // 2%
    uint256 public arbitrageFeeRate = 1000; // 10% of profit
    uint256 public flashLoanFeeRate = 9; // 0.09%
    uint256 public commodityStorageFeeRate = 100; // 1% annually
    uint256 public maxFlashLoanAmount = 1000000 * 10**18; // 1M tokens

    // Events for new functionality
    event DynamicHedgeCreated(uint256 indexed hedgeId, address portfolio, DynamicHedgeType hedgeType);
    event HedgeRebalanced(uint256 indexed hedgeId, uint256 oldRatio, uint256 newRatio, uint256 cost);
    event PortfolioInsuranceActivated(uint256 indexed insuranceId, address portfolio, uint256 floorValue);
    event InsuranceClaimed(uint256 indexed insuranceId, uint256 claimAmount, uint256 portfolioValue);
    event ArbitrageOpportunityDetected(uint256 indexed arbId, ArbitrageType arbType, uint256 expectedProfit);
    event ArbitrageExecuted(uint256 indexed arbId, address executor, uint256 actualProfit);
    event LiquidityMiningRewardsClaimed(address indexed provider, uint256 amount, LiquidityMiningTier tier);
    event FlashLoanExecuted(uint256 indexed loanId, address borrower, uint256 amount, uint256 profit);
    event CommodityOptionCreated(uint256 indexed optionId, CommodityType commodity, bool physicalDelivery);
    event EconomicDataSettlement(uint256 indexed derivativeId, EconomicIndicator indicator, uint256 actualValue);
    event CorrelationUpdated(address indexed asset1, address indexed asset2, int256 correlation);
    event GreeksCalculated(uint256 indexed optionId, int256 delta, uint256 gamma, int256 theta);
    event BasketOptionCreated(uint256 indexed optionId, address[] assets, uint256[] weights);

    constructor(address _governanceToken) Ownable(msg.sender) EIP712("AdvancedOptionsTradingPlatform", "6.0") {
        // Initialize correlation engine
        correlationEngine.lookbackPeriod = 30; // 30 days
        correlationEngine.updateFrequency = 86400; // Daily updates
        correlationEngine.isActive = true;
        
        // Initialize Greeks calculator
        greeksCalculator.calculationFrequency = 3600; // Hourly updates
    }

    // NEW FUNCTIONS START HERE

    /**
     * Create dynamic hedging strategy
     */
    function createDynamicHedge(
        address _portfolio,
        DynamicHedgeType _hedgeType,
        uint256 _targetRatio,
        uint256 _rebalanceThreshold,
        address[] calldata _hedgingInstruments,
        uint256[] calldata _hedgeWeights
    ) external payable nonReentrant {
        require(_hedgingInstruments.length == _hedgeWeights.length, "Array length mismatch");
        require(msg.value >= hedgingFeeRate * _targetRatio / 10000, "Insufficient hedging fee");
        
        uint256 hedgeId = dynamicHedgeCounter++;
        
        DynamicHedge storage hedge = dynamicHedges[hedgeId];
        hedge.hedgeId = hedgeId;
        hedge.portfolio = _portfolio;
        hedge.hedgeType = _hedgeType;
        hedge.targetRatio = _targetRatio;
        hedge.currentRatio = 0;
        hedge.rebalanceThreshold = _rebalanceThreshold;
        hedge.lastRebalance = block.timestamp;
        hedge.rebalanceFrequency = 3600; // 1 hour default
        hedge.hedgingInstruments = _hedgingInstruments;
        hedge.hedgeWeights = _hedgeWeights;
        hedge.isActive = true;
        
        emit DynamicHedgeCreated(hedgeId, _portfolio, _hedgeType);
    }

    /**
     * Rebalance dynamic hedge
     */
    function rebalanceDynamicHedge(uint256 _hedgeId) external nonReentrant {
        DynamicHedge storage hedge = dynamicHedges[_hedgeId];
        require(hedge.isActive, "Hedge not active");
        require(
            block.timestamp >= hedge.lastRebalance + hedge.rebalanceFrequency,
            "Rebalance too frequent"
        );
        
        // Calculate current hedge ratio (simplified)
        uint256 newRatio = _calculateHedgeRatio(_hedgeId);
        uint256 deviation = newRatio > hedge.targetRatio ? 
            newRatio - hedge.targetRatio : hedge.targetRatio - newRatio;
        
        require(deviation >= hedge.rebalanceThreshold, "Rebalance not needed");
        
        uint256 rebalanceCost = deviation * hedgingFeeRate / 10000;
        hedge.hedgingCost = hedge.hedgingCost.add(rebalanceCost);
        hedge.currentRatio = newRatio;
        hedge.lastRebalance = block.timestamp;
        
        emit HedgeRebalanced(_hedgeId, hedge.currentRatio, newRatio, rebalanceCost);
    }

    /**
     * Create portfolio insurance
     */
    function createPortfolioInsurance(
        address _portfolio,
        PortfolioInsuranceType _insuranceType,
        uint256 _floorValue,
        uint256 _multiplier,
        uint256 _duration
    ) external payable nonReentrant {
        uint256 premium = _floorValue * insurancePremiumRate / 10000;
        require(msg.value >= premium, "Insufficient premium");
        
        uint256 insuranceId = portfolioInsuranceCounter++;
        
        PortfolioInsurance storage insurance = portfolioInsurances[insuranceId];
        insurance.insuranceId = insuranceId;
        insurance.insuredPortfolio = _portfolio;
        insurance.insuranceType = _insuranceType;
        insurance.floorValue = _floorValue;
        insurance.multiplier = _multiplier;
        insurance.premiumPaid = premium;
        insurance.startTime = block.timestamp;
        insurance.duration = _duration;
        insurance.isActive = true;
        
        emit PortfolioInsuranceActivated(insuranceId, _portfolio, _floorValue);
    }

    /**
     * Claim portfolio insurance
     */
    function claimPortfolioInsurance(uint256 _insuranceId, uint256 _currentPortfolioValue) external nonReentrant {
        PortfolioInsurance storage insurance = portfolioInsurances[_insuranceId];
        require(insurance.isActive, "Insurance not active");
        require(_currentPortfolioValue < insurance.floorValue, "Portfolio above floor");
        require(
            block.timestamp <= insurance.startTime + insurance.duration,
            "Insurance expired"
        );
        
        uint256 claimAmount = insurance.floorValue - _currentPortfolioValue;
        insurance.totalClaims = insurance.totalClaims.add(claimAmount);
        
        // Transfer claim amount (implementation depends on payment method)
        payable(msg.sender).transfer(claimAmount);
        
        emit InsuranceClaimed(_insuranceId, claimAmount, _currentPortfolioValue);
    }

    /**
     * Detect arbitrage opportunities
     */
    function detectArbitrageOpportunity(
        ArbitrageType _arbType,
        address[] calldata _assets,
        uint256[] calldata _prices,
        uint256 _expectedProfit,
        uint256 _requiredCapital
    ) external {
        require(_assets.length == _prices.length, "Array length mismatch");
        require(_expectedProfit > 0, "No profit opportunity");
        
        uint256 arbId = arbitrageCounter++;
        
        ArbitrageOpportunity storage arb = arbitrageOpportunities[arbId];
        arb.arbId = arbId;
        arb.arbType = _arbType;
        arb.assets = _assets;
        arb.prices = _prices;
        arb.expectedProfit = _expectedProfit;
        arb.requiredCapital = _requiredCapital;
        arb.riskScore = _calculateArbitrageRisk(_arbType, _expectedProfit, _requiredCapital);
        arb.timeWindow = 300; // 5 minutes default
        arb.discoveredAt = block.timestamp;
        
        emit ArbitrageOpportunityDetected(arbId, _arbType, _expectedProfit);
    }

    /**
     * Execute arbitrage opportunity
     */
    function executeArbitrage(uint256 _arbId) external payable nonReentrant {
        ArbitrageOpportunity storage arb = arbitrageOpportunities[_arbId];
        require(!arb.isExecuted, "Already executed");
        require(
            block.timestamp <= arb.discoveredAt + arb.timeWindow,
            "Opportunity expired"
        );
        require(msg.value >= arb.requiredCapital, "Insufficient capital");
        
        // Execute arbitrage strategy (simplified)
        uint256 actualProfit = _executeArbitrageStrategy(_arbId);
        
        arb.isExecuted = true;
        arb.executor = msg.sender;
        arb.actualProfit = actualProfit;
        
        // Pay executor (after deducting platform fee)
        uint256 platformFee = actualProfit * arbitrageFeeRate / 10000;
        uint256 executorProfit = actualProfit.sub(platformFee);
        
        payable(msg.sender).transfer(executorProfit);
        
        emit ArbitrageExecuted(_arbId, msg.sender, actualProfit);
    }

    /**
     * Start liquidity mining
     */
    function startLiquidityMining(
        uint256 _stakedAmount,
        uint256 _lockupPeriod,
        LiquidityMiningTier _tier
    ) external payable nonReentrant {
        require(msg.value >= _stakedAmount, "Insufficient stake");
        require(_lockupPeriod >= 86400, "Minimum 1 day lockup"); // 1 day minimum
        
        LiquidityMining storage mining = liquidityMining[msg.sender];
        mining.provider = msg.sender;
        mining.tier = _tier;
        mining.stakedAmount = _stakedAmount;
        mining.stakingStart = block.timestamp;
        mining.lockupPeriod = _lockupPeriod;
        mining.lastClaimTime = block.timestamp;
        mining.isActive = true;
        
        // Set tier-based parameters
        if (_tier == LiquidityMiningTier.BRONZE) {
            mining.rewardRate = 1e15; // 0.001 tokens per second
            mining.multiplier = 10000; // 1x
        } else if (_tier == LiquidityMiningTier.SILVER) {
            mining.rewardRate = 15e14; // 0.0015 tokens per second
            mining.multiplier = 12000; // 1.2x
        } else if (_tier == LiquidityMiningTier.GOLD) {
            mining.rewardRate = 2e15; // 0.002 tokens per second
            mining.multiplier = 15000; // 1.5x
        }
    }

    /**
     * Claim liquidity mining rewards
     */
    function claimLiquidityRewards() external nonReentrant {
        LiquidityMining storage mining = liquidityMining[msg.sender];
        require(mining.isActive, "Mining not active");
        
        uint256 timeElapsed = block.timestamp.sub(mining.lastClaimTime);
        uint256 baseRewards = timeElapsed.mul(mining.rewardRate);
        uint256 totalRewards = baseRewards.mul(mining.multiplier).div(10000);
        
        mining.accumulatedRewards = mining.accumulatedRewards.add(totalRewards);
        mining.lastClaimTime = block.timestamp;
        
        // Transfer rewards (implementation depends on reward token)
        emit LiquidityMiningRewardsClaimed(msg.sender, totalRewards, mining.tier);
    }

    /**
     * Request flash loan
     */
    function requestFlashLoan(
        address _asset,
        uint256 _amount,
        FlashLoanType _loanType,
        bytes calldata _executionData,
        string calldata _strategy
    ) external nonReentrant {
        require(_amount <= maxFlashLoanAmount, "Amount exceeds limit");
        
        uint256 fee = _amount.mul(flashLoanFeeRate).div(10000);
        uint256 loanId = flashLoanCounter++;
        
        FlashLoanRequest storage loan = flashLoanRequests[loanId];
        loan.loanId = loanId;
        loan.borrower = msg.sender;
        loan.asset = _asset;
        loan.amount = _amount;
        loan.loanType = _loanType;
        loan.fee = fee;
        loan.executionData = _executionData;
        loan.timestamp = block.timestamp;
        loan.strategy = _strategy;
        
        // Execute flash loan logic
        bool success = _executeFlashLoan(loanId);
        require(success, "Flash loan execution failed");
        
        loan.isExecuted = true;
        loan.isRepaid = true;
        
        emit FlashLoanExecuted(loanId, msg.sender, _amount, 0);
    }

    /**
     * Create commodity option
     */
    function createCommodityOption(
        CommodityType _commodity,
        uint256 _contractSize,
        uint256 _strikePrice,
        uint256 _premium,
        uint256 _expiry,
        OptionType _optionType,
        bool _physicalDelivery,
        string calldata _deliveryLocation
    ) external payable nonReentrant {
        require(msg.value >= _premium, "Insufficient premium");
        require(_expiry > block.timestamp, "Expiry in past");
        
        uint256 optionId = commodityOptionCounter++;
        
        CommodityOption storage option = commodityOptions[optionId];
        option.id = optionId;
        option.commodity = _commodity;
        option.contractSize = _contractSize;
        option.strikePrice = _strikePrice;
        option.premium = _premium;
        option.expiry = _expiry;
        option.optionType = _optionType;
        option.creator = msg.sender;
        option.physicalDelivery = _physicalDelivery;
        option.deliveryLocation = _deliveryLocation;
        option.isActive = true;
        
        // Set commodity-specific parameters
        if (_commodity == CommodityType.GOLD) {
            option.storageFeesPerDay = _premium.mul(5).div(36500); // 0.05% annually
            option.qualityGrade = 9999; // 99.99% purity
        } else if (_commodity == CommodityType.OIL) {
            option.storageFeesPerDay = _premium.mul(10).div(36500); // 0.1% annually
            option.qualityGrade = 40; // API gravity
        }
        
        emit CommodityOptionCreated(optionId, _commodity, _physicalDelivery);
    }

    /**
     * Create economic derivative
     */
    function createEconomicDerivative(
        EconomicIndicator _indicator,
        uint256 _strikeValue,
        uint256 _premium,
        uint256 _expiry,
        OptionType _optionType,
        string calldata _dataSource
    ) external payable nonReentrant {
        require(msg.value >= _premium, "Insufficient premium");
        require(_expiry > block.timestamp, "Expiry in past");
        
        uint256 derivativeId = economicDerivativeCounter++;
        
        EconomicDerivative storage derivative = economicDerivatives[derivativeId];
        derivative.id = derivativeId;
        derivative.indicator = _indicator;
        derivative.strikeValue = _strikeValue;
        derivative.premium = _premium;
        derivative.expiry = _expiry;
        derivative.optionType = _optionType;
        derivative.creator = msg.sender;
        derivative.dataSource = _dataSource;
        derivative.settlementDelay = 5; // 5 days after expiry
        
        emit EconomicDataSettlement(derivativeId, _indicator, 0);
    }

    /**
     * Create basket option
     */
    function createBasketOption(
        address[] calldata _underlyingAssets,
        uint256[] calldata _weights,
        uint256 _strikePrice,
        uint256 _premium,
        uint256 _expiry,
        OptionType _optionType
    ) external payable nonReentrant {
        require(_underlyingAssets.length == _weights.length, "Array length mismatch");
        require(msg.value >= _premium, "Insufficient premium");
        
        // Verify weights sum to 100%
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < _weights.length; i++) {
            totalWeight = totalWeight.add(_weights[i]);
        }
        require(totalWeight == 10000, "Weights must sum to 100%");
        
        uint256 optionId = basketOptionCounter++;
        
        BasketOption storage option = basketOptions[optionId];
        option.id = optionId;
        option.underlyingAssets = _underlyingAssets;
        option.weights = _weights;
        option.strikePrice = _strikePrice;
        option.premium = _premium;
        option.expiry = _expiry;
        option.optionType = _optionType;
        option.creator = msg.sender;
        option.isActive = true;
        
        // Store initial asset prices for basket value calculation
        for (uint256
   
      
        
       
        
       
        
        

   
    
     
       
        
       
        
       
       
        
       
        
        
