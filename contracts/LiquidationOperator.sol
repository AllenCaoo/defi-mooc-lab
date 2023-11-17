//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "hardhat/console.sol";

// ----------------------INTERFACE------------------------------

// Aave
// https://docs.aave.com/developers/the-core-protocol/lendingpool/ilendingpool

interface ILendingPool {
    /**
     * Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
     * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of theliquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param receiveAToken `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants
     * to receive the underlying collateral asset directly
     **/
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;

    /**
     * Returns the user account data across all the reserves
     * @param user The address of the user
     * @return totalCollateralETH the total collateral in ETH of the user
     * @return totalDebtETH the total debt in ETH of the user
     * @return availableBorrowsETH the borrowing power left of the user
     * @return currentLiquidationThreshold the liquidation threshold of the user
     * @return ltv the loan to value of the user
     * @return healthFactor the current health factor of the user
     **/
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
}

// UniswapV2

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IERC20.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/Pair-ERC-20
interface IERC20 {
    // Returns the account balance of another account with address _owner.
    function balanceOf(address owner) external view returns (uint256);

    /**
     * Allows _spender to withdraw from your account multiple times, up to the _value amount.
     * If this function is called again it overwrites the current allowance with _value.
     * Lets msg.sender set their allowance for a spender.
     **/
    function approve(address spender, uint256 value) external; // return type is deleted to be compatible with USDT

    /**
     * Transfers _value amount of tokens to address _to, and MUST fire the Transfer event.
     * The function SHOULD throw if the message caller’s account balance does not have enough tokens to spend.
     * Lets msg.sender send pool tokens to an address.
     **/
    function transfer(address to, uint256 value) external returns (bool);
}

// https://github.com/Uniswap/v2-periphery/blob/master/contracts/interfaces/IWETH.sol
interface IWETH is IERC20 {
    // Convert the wrapped token back to Ether.
    function withdraw(uint256) external;
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Callee.sol
// The flash loan liquidator we plan to implement this time should be a UniswapV2 Callee
interface IUniswapV2Callee {
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Factory.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/factory
interface IUniswapV2Factory {
    // Returns the address of the pair for tokenA and tokenB, if it has been created, else address(0).
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Pair.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/pair
interface IUniswapV2Pair {
    /**
     * Swaps tokens. For regular swaps, data.length must be 0.
     * Also see [Flash Swaps](https://docs.uniswap.org/protocol/V2/concepts/core-concepts/flash-swaps).
     **/
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    /**
     * Returns the reserves of token0 and token1 used to price trades and distribute liquidity.
     * See Pricing[https://docs.uniswap.org/protocol/V2/concepts/advanced-topics/pricing].
     * Also returns the block.timestamp (mod 2**32) of the last block during which an interaction occured for the pair.
     **/
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}




// Import the IUniswapV2Router02 interface
interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    // Add other necessary functions from the Uniswap router contract
    // ...
}


// ----------------------IMPLEMENTATION------------------------------

contract Logger {
    event Log(string message);

    function log() public {
        // Log a message
        emit Log("Something happened!");
    }
}


contract LiquidationOperator is IUniswapV2Callee {
    uint8 public constant health_factor_decimals = 18;

    // TODO: define constants used in the contract including ERC-20 tokens, Uniswap Pairs, Aave lending pools, etc. */
    //    *** Your code here ***
    address user = 0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F;
    uint256 liquid_time = 12489620;

    ILendingPool constant AAVE_LENDING_POOL = ILendingPool(address(0x007d2768de32b0b80b7a3454c06bdac94a69ddc7a9));
    IERC20 constant USDT_POOL = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IWETH constant WETH_POOL = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); 
    IERC20 constant WBTC_POOL = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599); 
    address constant UNISWAP_ADDRESS = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address me = address(this);

    uint256 constant debt_USDT = 1600000000000;

    IUniswapV2Factory factory = IUniswapV2Factory(UNISWAP_ADDRESS); 
    IUniswapV2Pair pair_WBTC_WETH = IUniswapV2Pair(factory.getPair(address(WBTC_POOL), address(WETH_POOL)));
    IUniswapV2Pair pair_WETH_USDT = IUniswapV2Pair(factory.getPair(address(WETH_POOL), address(USDT_POOL)));
    
    string constant NONEMPTY_STRING = "any data :)";

    // END TODO

    // some helper function, it is totally fine if you can finish the lab without using these function
    // https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    // safe mul is not necessary since https://docs.soliditylang.org/en/v0.8.9/080-breaking-changes.html
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // some helper function, it is totally fine if you can finish the lab without using these function
    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    // safe mul is not necessary since https://docs.soliditylang.org/en/v0.8.9/080-breaking-changes.html
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    constructor() {
        // TODO: (optional) initialize your contract
        //   *** Your code here ***
        // END TODO
        
    }

    // TODO: add a `receive` function so that you can withdraw your WETH
    //   *** Your code here ***
    receive() external payable {} 
    // END TODO

    // required by the testing script, entry for your liquidation call
    function operate() external {
        // TODO: implement your liquidation logic

        // 0. security checks and initializing variables
        //    *** Your code here ***
        // TODO: Add security checks in here

        // 1. get the target user account data & make sure it is liquidatable
        //    *** Your code here ***
        (, , , , , uint256 healthFactor) = AAVE_LENDING_POOL.getUserAccountData(user);

        require(healthFactor < 10**health_factor_decimals, "Target user cannot be liquidated.");
        
        // 2. call flash swap to liquidate the target user
        // based on https://etherscan.io/tx/0xac7df37a43fab1b130318bbb761861b8357650db2e2c6493b73d6da3d9581077
        // we know that the target user borrowed USDT with WBTC as collateral
        // we should borrow USDT, liquidate the target user and get the WBTC, then swap WBTC to repay uniswap
        // (please feel free to develop other workflows as long as they liquidate the target user successfully)
        //    *** Your code here ***

        // (uint112 WETH_reserve, uint112 USDT_reserve, ) = pair_WETH_USDT.getReserves();
        bytes memory data = abi.encode(NONEMPTY_STRING);
        pair_WETH_USDT.swap(0, debt_USDT, me, data);   // perform "flash" swap (1st reg swap)


        // 3. Convert the profit into ETH and send back to sender (liquidation?)
        //    *** Your code here ***
        WETH_POOL.withdraw(WETH_POOL.balanceOf(me));  // withdraw balance from intermediary
        payable(msg.sender).transfer(me.balance);  // send balance over
        

        // END TODO
    }

    // required by the swap
    function uniswapV2Call(
        address,
        uint256,
        uint256 debtCover,
        bytes calldata
    ) external override {
        // TODO: implement your liquidation logic

        // 2.0. security checks and initializing variables
        //    *** Your code here ***
        /* TODO: ADD MORE SECURITY CHECKS */
        require(debtCover > 0, "Debt is less than 0.");
        require(msg.sender == address(pair_WETH_USDT), "Wrong sender.");
        (uint256 WETH_reserve1, uint256 USDT_reserve, ) = pair_WETH_USDT.getReserves(); // WETH <=> USDT pool
        (uint256 WBTC_reserve, uint256 WETH_reserve2, ) = pair_WBTC_WETH.getReserves(); // WBTC <=> WETH pool
        address exchange1 = address(pair_WBTC_WETH);
        address exchange2 = address(pair_WETH_USDT);

        // 2.1 liquidate the target user
        //    *** Your code here ***
        USDT_POOL.approve(address(AAVE_LENDING_POOL), debtCover);
        AAVE_LENDING_POOL.liquidationCall(
                                address(WBTC_POOL), 
                                address(USDT_POOL), 
                                address(user), 
                                debtCover, 
                                false);  // liquidation call

        // 2.2 swap WBTC for other things or repay directly
        //    *** Your code here ***
        uint WBTC_collat = WBTC_POOL.balanceOf(me);  // intermediate balance = WBTC_collat
        WBTC_POOL.transfer(exchange1, WBTC_collat);
        uint amountOut_WETH = getAmountOut(WBTC_collat, WBTC_reserve, WETH_reserve2);
        pair_WBTC_WETH.swap(0, amountOut_WETH, me, "");  // perform 2nd regular swap


        // 2.3 repay WETH
        //    *** Your code here ***
        uint WETH_repay = getAmountIn(debtCover, WETH_reserve1, USDT_reserve); 
        WETH_POOL.transfer(exchange2, WETH_repay);
        
        // END TODO
    }
}
