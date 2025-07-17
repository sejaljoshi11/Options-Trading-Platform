// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract OptionsTradingPlatform is ReentrancyGuard, Ownable {
    using SafeMath for uint256;

    enum OptionType { CALL, PUT }
    enum OptionState { ACTIVE, EXPIRED, EXERCISED }

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
    }

    struct PriceData {
        uint256 price;
        uint256 timestamp;
    }

    mapping(uint256 => Option) public options;
    mapping(address => PriceData) public assetPrices;
    mapping(address => uint256[]) public userOptions;
    mapping(address => mapping(address => uint256)) public collateral;
    
    uint256 public optionCounter;
    uint256 public constant EXERCISE_WINDOW = 1 hours;
    uint256 public constant PRICE_VALIDITY_DURATION = 1 hours;
    uint256 public platformFee = 100; // 1% = 100 basis points
    uint256 public constant BASIS_POINTS = 10000;

    event OptionCreated(
        uint256 indexed optionId,
        address indexed creator,
        address indexed underlyingAsset,
        uint256 strikePrice,
        uint256 premium,
        uint256 expiry,
        OptionType optionType
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

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Creates a new option contract
     * @param _underlyingAsset Address of the underlying asset
     * @param _strikePrice Strike price in wei
     * @param _premium Premium amount in wei
     * @param _expiry Expiry timestamp
     * @param _amount Amount of underlying asset
     * @param _optionType Type of option (CALL or PUT)
     */
    function createOption(
        address _underlyingAsset,
        uint256 _strikePrice,
        uint256 _premium,
        uint256 _expiry,
        uint256 _amount,
        OptionType _optionType
    ) external payable nonReentrant validPrice(_underlyingAsset) {
        require(_underlyingAsset != address(0), "Invalid asset address");
        require(_strikePrice > 0, "Strike price must be greater than 0");
        require(_premium > 0, "Premium must be greater than 0");
        require(_expiry > block.timestamp, "Expiry must be in the future");
        require(_amount > 0, "Amount must be greater than 0");

        uint256 optionId = optionCounter++;
        uint256 requiredCollateral = calculateRequiredCollateral(_strikePrice, _amount, _optionType);

        // For CALL options, creator must deposit underlying asset as collateral
        if (_optionType == OptionType.CALL) {
            require(
                collateral[msg.sender][_underlyingAsset] >= _amount,
                "Insufficient collateral for CALL option"
            );
            collateral[msg.sender][_underlyingAsset] = collateral[msg.sender][_underlyingAsset].sub(_amount);
        } else {
            // For PUT options, creator must deposit ETH as collateral
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
            isCollateralized: true
        });

        userOptions[msg.sender].push(optionId);

        emit OptionCreated(
            optionId,
            msg.sender,
            _underlyingAsset,
            _strikePrice,
            _premium,
            _expiry,
            _optionType
        );
    }

    /**
     * @dev Purchases an existing option
     * @param _optionId ID of the option to purchase
     */
    function purchaseOption(uint256 _optionId) external payable nonReentrant optionExists(_optionId) {
        Option storage option = options[_optionId];
        require(option.state == OptionState.ACTIVE, "Option is not active");
        require(option.buyer == address(0), "Option already purchased");
        require(block.timestamp < option.expiry, "Option has expired");
        require(msg.sender != option.creator, "Cannot buy your own option");

        uint256 totalCost = option.premium.add(option.premium.mul(platformFee).div(BASIS_POINTS));
        require(msg.value >= totalCost, "Insufficient payment");

        option.buyer = msg.sender;
        userOptions[msg.sender].push(_optionId);

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

        emit OptionPurchased(_optionId, msg.sender, option.premium);
    }

    /**
     * @dev Exercises an option contract
     * @param _optionId ID of the option to exercise
     */
    function exerciseOption(uint256 _optionId) external nonReentrant optionExists(_optionId) onlyOptionBuyer(_optionId) validPrice(options[_optionId].underlyingAsset) {
        Option storage option = options[_optionId];
        require(option.state == OptionState.ACTIVE, "Option is not active");
        require(block.timestamp <= option.expiry.add(EXERCISE_WINDOW), "Exercise window has closed");

        uint256 currentPrice = assetPrices[option.underlyingAsset].price;
        uint256 profit = 0;

        if (option.optionType == OptionType.CALL) {
            // CALL option: profit if current price > strike price
            if (currentPrice > option.strikePrice) {
                profit = currentPrice.sub(option.strikePrice).mul(option.amount).div(1e18);
                require(address(this).balance >= profit, "Insufficient contract balance");
                
                (bool success, ) = msg.sender.call{value: profit}("");
                require(success, "Profit transfer failed");
            }
        } else {
            // PUT option: profit if current price < strike price
            if (currentPrice < option.strikePrice) {
                profit = option.strikePrice.sub(currentPrice).mul(option.amount).div(1e18);
                require(address(this).balance >= profit, "Insufficient contract balance");
                
                (bool success, ) = msg.sender.call{value: profit}("");
                require(success, "Profit transfer failed");
            }
        }

        option.state = OptionState.EXERCISED;

        // Release collateral back to creator if option was not profitable
        if (profit == 0) {
            if (option.optionType == OptionType.CALL) {
                collateral[option.creator][option.underlyingAsset] = collateral[option.creator][option.underlyingAsset].add(option.amount);
            } else {
                uint256 collateralAmount = calculateRequiredCollateral(option.strikePrice, option.amount, option.optionType);
                (bool success, ) = option.creator.call{value: collateralAmount}("");
                require(success, "Collateral return failed");
            }
        }

        emit OptionExercised(_optionId, msg.sender, profit);
    }

    // Admin and utility functions
    function updateAssetPrice(address _asset, uint256 _price) external onlyOwner {
        require(_asset != address(0), "Invalid asset address");
        require(_price > 0, "Price must be greater than 0");
        
        assetPrices[_asset] = PriceData({
            price: _price,
            timestamp: block.timestamp
        });

        emit PriceUpdated(_asset, _price, block.timestamp);
    }

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
            return _amount; // For CALL, collateral is the underlying asset amount
        } else {
            return _strikePrice.mul(_amount).div(1e18); // For PUT, collateral is strike price * amount
        }
    }

    // View functions
    function getOption(uint256 _optionId) external view optionExists(_optionId) returns (Option memory) {
        return options[_optionId];
    }

    function getUserOptions(address _user) external view returns (uint256[] memory) {
        return userOptions[_user];
    }

    function getAssetPrice(address _asset) external view returns (uint256, uint256) {
        PriceData memory data = assetPrices[_asset];
        return (data.price, data.timestamp);
    }

    function getUserCollateral(address _user, address _asset) external view returns (uint256) {
        return collateral[_user][_asset];
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

    // Emergency functions
    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 1000, "Fee cannot exceed 10%"); // Max 10%
        platformFee = _fee;
    }

    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Emergency withdrawal failed");
    }

    receive() external payable {}
}
