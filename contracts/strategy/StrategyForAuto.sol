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
import  "../interfaces/auto/IAutoPool.sol";
/*

 A strategy must implement the following calls;
 
 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()
 
 Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller
 
*/

contract StrategyForAuto is IGOFStrategy, Ownable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    address public want;
    address public output;
    uint256 public pid;
    address public autoPool;
    address public swapRouter;

    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public gof = address(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
    
    uint public burnfee = 400;
    uint public fee = 100;
    uint public foundationfee = 400;
    uint public callfee = 0;
    uint public max = 900;

    uint public reservesRate = 90;
    uint constant public cashMax = 1000;
    bool public splitGof = true;

    uint public withdrawalFee = 0;
    uint constant public withdrawalMax = 10000;
    
    address public strategyDev;
    address public controller;
    address public foundationAddress = address(0x1250E38187Ff89d05f99F3fa0E324241bbE2120C);
    address public burnAddress;

    string public getName;

    address[] public swap2GOFRouting;
    address[] public swap2TokenRouting;

    modifier checkStrategist(){
        require(msg.sender == strategyDev || msg.sender == owner(), "Golff:!strategist");
        _;
    }
    
    constructor(address _controller, 
            uint256 _pid, 
            address _want,
            address _output,
            address _poolAddress,
            address _routerAddress, 
            address _burnAddress) public {
        strategyDev = tx.origin;
        controller = _controller;
        pid = _pid;
        want = _want;
        output = _output;
        getName = string(abi.encodePacked("Golff:Strategy:", ERC20(want).name()));
        autoPool = _poolAddress;
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
        uint _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            IERC20(want).safeApprove(autoPool, 0);
            IERC20(want).safeApprove(autoPool, _want);
            IAutoPool(autoPool).deposit(pid, _want);
        }
    }
    
    // Controller only function for creating additional rewards from dust
    function withdraw(address _asset) external override {
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
        
        uint _fee = 0;
        if (withdrawalFee>0){
            _fee = _amount.mul(withdrawalFee).div(withdrawalMax);        
            IERC20(want).safeTransfer(IGOFController(controller).getRewards(), _fee);
        }
        
        address _vault = IGOFController(controller).getVaults(address(want));
        require(_vault != address(0), "Golff:!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
    }
    
    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external override returns (uint balance) {
        require(msg.sender == controller, "Golff:!controller");
        _withdrawAll();
        
        
        balance = IERC20(want).balanceOf(address(this));
        
        address _vault = IGOFController(controller).getVaults(address(want));
        require(_vault != address(0), "Golff:!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);
    }
    
    function _withdrawAll() internal {
        uint256 balance = balanceOfPool();
        if(balance > 0){
            IAutoPool(autoPool).withdrawAll(pid);
        }
    }

    function _withdrawSome(uint256 _amount) internal returns (uint) {
        IAutoPool(autoPool).withdraw(pid, _amount);
        return _amount;
    }
    
    function harvest() external checkStrategist {
        uint _before = IERC20(want).balanceOf(address(this));
        IAutoPool(autoPool).withdraw(pid, 0);
        //判断收益情况
        doswap();
        uint _a = IERC20(want).balanceOf(address(this)).sub(_before);
        uint _sb = _a.mul(reservesRate).div(cashMax);
        //分hgof
        dosplit(_sb);
        //复投
        deposit();
    }

    function doswap() internal {
        uint256 _balance = IERC20(output).balanceOf(address(this));
        if(_balance > 0 && output != want){
            ISwapRouter(swapRouter).swapExactTokensForTokens(_balance, 0, swap2TokenRouting, address(this), now.add(1800));
        }
    }

    function dosplit(uint256 _b) internal{
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
    
    function balanceOfWant() public view returns (uint) {
        return IERC20(want).balanceOf(address(this));
    }
    
    function balanceOfPool() public view returns (uint) {
       (uint256 amount, ) = IAutoPool(autoPool).userInfo(pid, address(this));
        return amount;
    }
    
    function balanceOf() public view override returns (uint) {
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