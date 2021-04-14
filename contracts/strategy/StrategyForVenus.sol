// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import  "../interfaces/IGOFStrategy.sol";
import  "../interfaces/IGOFController.sol";
import  "../interfaces/ISwapRouter.sol";
import  "../interfaces/venus/IVenusPool.sol";
import  "../interfaces/venus/IVenusBNBPool.sol";
import  "../interfaces/venus/IUnitroller.sol";
import  "../interfaces/IWBNB.sol";
/*

 A strategy must implement the following calls;
 
 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()
 
 Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller
 
*/

contract StrategyForVenus is IGOFStrategy, Ownable{
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public want; //*
    address public output; //*
    address public venusPool; //*
    address public swapRouter;

    address constant public gof = address(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public unitroller = address(0xfD36E2c2a6789Db23113685031d7F16329158384);

    uint public burnfee = 400;
    uint public fee = 100;
    uint public foundationfee = 400;
    uint public callfee = 0;
    uint public max = 900;

    uint256 public exchangeRatePrior = 0;
    uint256 public cbalancePrior = 0;
    uint public reserves = 0;
    uint public reservesRate = 90;
    uint constant public cashMax = 1000;
    bool public splitGof = true;

    uint public withdrawalFee = 0;
    uint constant public withdrawalMax = 10000;
    
    address public strategyDev;
    address public controller;
    address public foundationAddress = address(0x79006B8548326C71bbF57a4384843Df2f578381F);
    address public burnAddress;

    string public getName;

    address[] public swap2GOFRouting;
    address[] public swap2TokenRouting;

    event UpdateCtokenInfo(uint256 _oldCtokenBalance, uint256 _newCtokenBalance, uint256 _oldExchangeRate, uint256 _newExchangeRate);

    event ClaimReserves(uint256 _amount);

    constructor(address _controller, 
            address _want,
            address _output,
            address _poolAddress,
            address _routerAddress,
            address _burnAddress) public {
        strategyDev = tx.origin;
        controller = _controller;
        want = _want;
        output = _output;
        getName = string(abi.encodePacked("Golff:Strategy:", ERC20(want).name()));
        venusPool = _poolAddress;
        swapRouter = _routerAddress;
        burnAddress = _burnAddress;
        
        swap2GOFRouting = [output, gof];
        swap2TokenRouting = [output, want];
        
        doApprove();
    }

    function getWant() external view override returns (address){
        return want;
    }

    function doApprove () public{
        IERC20(want).safeApprove(swapRouter, 0);
        IERC20(want).safeApprove(swapRouter, uint(-1));

        IERC20(output).safeApprove(swapRouter, 0);
        IERC20(output).safeApprove(swapRouter, uint(-1));
    }
    
    function deposit() public override {
        doDeposit();
        updateUnclaimReserves();
    }

    function updateUnclaimReserves() internal {
        (, uint256 poolBal, , uint256 exchangeRate) =
            IVenusPool(venusPool).getAccountSnapshot(address(this));
        reserves = reserves.add(calcRserves(exchangeRate));
        uint _oldExchangeRate = exchangeRatePrior;
        exchangeRatePrior = exchangeRate;
        uint _old = cbalancePrior;
        cbalancePrior = poolBal;
        emit UpdateCtokenInfo(_old, cbalancePrior, _oldExchangeRate, exchangeRatePrior);
    }

    function claimReserves(uint _r) public checkStrategist {
        require(_r <= reserves, "Strategy:INSUFFICIENT_UNCLAIM");
        reserves = reserves.sub(_r);
        uint _balance = IERC20(want).balanceOf(address(this));

        if (_balance < _r) {
            _r = _withdrawSome(_r.sub(_balance));
            _r = _r.add(_balance);
            updateUnclaimReserves();
        }
        
        dosplit(_r);

        emit ClaimReserves(_r);
    }

    function claimReservesAll() public checkStrategist {
        claimReserves(reserves);
    }

    function doDeposit() internal {
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            if (want == wbnb) {
                IWBNB(wbnb).withdraw(_want);
                uint balance = address(this).balance;
                if (balance > 0) {
                    IVenusBNBPool(venusPool).mint{value: balance}();
                }
            } else {
                IERC20(want).safeApprove(venusPool, 0);
                IERC20(want).safeApprove(venusPool, _want);
                require(IVenusPool(venusPool).mint(_want) == 0, "Strategy mint:error");
            }
        }
    }
    
    // Controller only function for creating additional rewards from dust
    function withdraw(address _asset) external override{
        require(msg.sender == controller, "Golff:!controller");
        require(want != address(_asset), "Golff:want");
        uint256 balance = IERC20(_asset).balanceOf(address(this));
        IERC20(_asset).safeTransfer(controller, balance);
    }
    
    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint _amount) external override {
        require(msg.sender == controller, "Golff:!controller");

        uint _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }
        updateUnclaimReserves();
        
        uint _fee = 0;
        if (withdrawalFee>0){
            _fee = _amount.mul(withdrawalFee).div(withdrawalMax);        
            IERC20(want).safeTransfer(IGOFController(controller).getRewards(), _fee);
        }
        
        address _vault = IGOFController(controller).getVaults(address(want));
        require(_vault != address(0), "Golff:!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));

    }

    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        uint256 before = IERC20(want).balanceOf(address(this));
        if (want == wbnb) {
            require(IVenusBNBPool(venusPool).redeemUnderlying(_amount) == 0, "Strategy redeemUnderlying:error");
            uint balance = address(this).balance;
            if (balance > 0) {
                IWBNB(want).deposit{value: balance}();
            }
        } else {
            require(IVenusPool(venusPool).redeemUnderlying(_amount) == 0, "Strategy redeemUnderlying:error");
        }
        return IERC20(want).balanceOf(address(this)).sub(before);
    }
    
    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external override returns (uint balance) {
        require(msg.sender == controller, "Golff:!controller");

        _withdrawAll();
        updateUnclaimReserves();
        
        balance = IERC20(want).balanceOf(address(this));
        
        address _vault = IGOFController(controller).getVaults(address(want));
        require(_vault != address(0), "Golff:!vault"); // additional protection so we don't burn the funds
        if (balance > reserves) {
            IERC20(want).safeTransfer(_vault, balance.sub(reserves));
        }

    }
    
    function _withdrawAll() internal {
        uint256 balance = IVenusPool(venusPool).balanceOf(address(this));
        if(balance > 0){
            uint result = IVenusPool(venusPool).redeem(balance);
            require(result == 0, "Strategy redeem:error");
        }
        if (want == wbnb) {
            uint _htb = address(this).balance;
            if (_htb > 0) {
                IWBNB(want).deposit{value: _htb}();
            }
        }
    }
    
    modifier checkStrategist(){
        require(msg.sender == strategyDev || msg.sender == owner(), "Golff:!strategist");
        _;
    }

    function harvest() external checkStrategist{
        uint _before = IERC20(want).balanceOf(address(this));
        //获取收益
        getReward();
        //兑换本位币
        doswap();
        uint _a = IERC20(want).balanceOf(address(this)).sub(_before);
        uint _sb = _a.mul(reservesRate).div(cashMax);
        //分gof
        dosplit(_sb);
        //复投
        doDeposit();
        updateUnclaimReserves();
    }

    function doswap() internal {
        uint256 _balance = IERC20(output).balanceOf(address(this));
        if(_balance > 0 && output != want){
            ISwapRouter(swapRouter).swapExactTokensForTokens(_balance, 0, swap2TokenRouting, address(this), now.add(1800));
        }
    }

    function dosplit(uint _b) internal{
        if (_b > 0) {
            if (splitGof) {
                ISwapRouter(swapRouter).swapExactTokensForTokens(_b, 0, swap2GOFRouting, address(this), now.add(1800));
                _b = IERC20(gof).balanceOf(address(this));
                split(gof, _b);
            } else {
                split(want, _b);
            }
        }
    }

    function split(address token, uint b) internal{
        if(b > 0){
            uint _callfee = b.mul(callfee).div(max);
            uint _foundationfee = b.mul(foundationfee).div(max);
            uint _burnfee = b.mul(burnfee).div(max); 
            uint _fee = b.sub(_callfee).sub(_foundationfee).sub(_burnfee);
            if (_fee > 0) {
                IERC20(token).safeTransfer(IGOFController(controller).getRewards(), _fee);
            }
            if (_callfee > 0) {
                IERC20(token).safeTransfer(msg.sender, _callfee); 
            }
            if (_foundationfee > 0) {
                IERC20(token).safeTransfer(foundationAddress, _foundationfee); 
            }
            if (_burnfee >0){
                IERC20(token).safeTransfer(burnAddress, _burnfee);
            }
        }
    }

    function getReward() internal {
        address[] memory markets = new address[](1);
        markets[0] = venusPool;
        IUnitroller(unitroller).claimVenus(address(this), markets);
    }

    function calcRserves(uint256 exchangeRate) internal view returns(uint) {
        return cbalancePrior.mul(exchangeRate.sub(exchangeRatePrior)).div(1e18).mul(reservesRate).div(cashMax);
    }

    function balanceOfPool() internal view returns (uint) {
        (, uint256 poolBal, , uint256 exchangeRate) =
            IVenusPool(venusPool).getAccountSnapshot(address(this));
        return poolBal.mul(exchangeRate).div(1e18);
    }
    
    function balanceOfWant() internal view returns (uint) {
        return IERC20(want).balanceOf(address(this));
    }
    
    function balanceOf() external view override returns (uint) {
        (, , , uint256 exchangeRate) = IVenusPool(venusPool).getAccountSnapshot(address(this));
        return balanceOfAll().sub(reserves).sub(calcRserves(exchangeRate));
    }
    
    function balanceOfAll() public view returns (uint) {
        return balanceOfWant()
               .add(balanceOfPool());
    }
    
    function setController(address _controller) public onlyOwner{
        controller = _controller;
    }
    
    function setFees(uint256 _foundationfee, uint256 _burnfee, uint256 _fee, uint256 _callfee) public onlyOwner{
        max = _fee.add(_callfee).add(_burnfee).add(_foundationfee);

        fee = _fee;
        callfee = _callfee;
        burnfee = _burnfee;
        foundationfee = _foundationfee;
    }

    function setReservesRate(uint256 _reservesRate) public onlyOwner {
        require(_reservesRate < cashMax, "reservesRate >= 1000");
        reservesRate = _reservesRate;
    }

    function setFoundationAddress(address _foundationAddress) public onlyOwner{
        foundationAddress = _foundationAddress;
    }

    function setWithdrawalFee(uint _withdrawalFee) public onlyOwner{
        require(_withdrawalFee <=100,"fee > 1%"); //max:1%
        withdrawalFee = _withdrawalFee;
    }
    
    function setBurnAddress(address _burnAddress) public onlyOwner{
        burnAddress = _burnAddress;
    }

    function setStrategyDev(address _strategyDev) public onlyOwner{
        strategyDev = _strategyDev;
    }

    function setRouter(address _routerAddress) public onlyOwner{
        swapRouter = _routerAddress;
    }

    function setSwap2Token(address[] memory _path) public onlyOwner{
        swap2TokenRouting = _path;
    }

    function setSwap2GOF(address[] memory _path) public onlyOwner{
        swap2GOFRouting = _path;
    }

    function setSplitGof() public onlyOwner{
        splitGof = !splitGof;
    }

    receive() external payable {}
}
    