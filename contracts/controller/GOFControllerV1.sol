// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "../interfaces/IGOFController.sol";
import "../interfaces/IGOFStrategy.sol";
import "../interfaces/ISwapRouter.sol";

interface Converter {
    function convert(address) external returns (uint);
}

contract GOFControllerV1 is IGOFController, Ownable{
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    address public strategist;
    address public onesplit;

    address public rewards;
    mapping(address => address) public vaults;
    mapping(address => address) public strategies;
    
    mapping(address => mapping(address => bool)) public approvedStrategies;

    uint public split = 500;
    uint public constant max = 10000;
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    constructor(address _rewards) public {
        strategist = msg.sender;
        onesplit = address(0x7DAe51BD3E3376B8c7c4900E9107f12Be3AF1bA8);//mdex
        rewards = _rewards;
    }
    
    modifier checkStrategist(){
        require(msg.sender == strategist || msg.sender == owner(), "Golff:!strategist");
        _;
    }

    function setStrategist(address account) external checkStrategist{
        strategist = account;
    }
    
    function setSplit(uint _split) external onlyOwner{
        split = _split;
    }
    
    function setOneSplit(address _onesplit) external onlyOwner{
        onesplit = _onesplit;
    }
    
    function setRewards(address _rewards) external onlyOwner{
        rewards = _rewards;
    }
    
    function approveStrategy(address _token, address _strategy) external onlyOwner{
        approvedStrategies[_token][_strategy] = true;
    }

    function revokeStrategy(address _token, address _strategy) external onlyOwner{
        approvedStrategies[_token][_strategy] = false;
    }

    function setVault(address _token, address _vault) external checkStrategist{
        require(vaults[_token] == address(0), "Golff:vault exist");
        vaults[_token] = _vault;
    }
    
    function setStrategy(address _token, address _strategy) external checkStrategist{
        require(approvedStrategies[_token][_strategy], "Golff:!approved");
        address _current = strategies[_token];
        if (_current != address(0)) {
           IGOFStrategy(_current).withdrawAll();
        }
        strategies[_token] = _strategy;
    }

    function getRewards() external view override returns (address){
        return rewards;
    }
    function getVaults(address _token) external view override returns (address){
        return vaults[_token];
    }
    
    function earn(address _token, uint _amount) public override{
        address _strategy = strategies[_token]; 
        address _want = IGOFStrategy(_strategy).getWant();
        require(_want == _token, "Golff:_want != _token");
        IERC20(_token).safeTransfer(_strategy, _amount);
        IGOFStrategy(_strategy).deposit();
    }
    
    function balanceOf(address _token) external view override returns (uint) {
        return IGOFStrategy(strategies[_token]).balanceOf();
    }
    
    function withdrawAll(address _token) public checkStrategist{
        IGOFStrategy(strategies[_token]).withdrawAll();
    }
    
    function inCaseTokensGetStuck(address _token, uint _amount) public checkStrategist{
        IERC20(_token).safeTransfer(owner(), _amount);
    }
    
    function inCaseStrategyTokenGetStuck(address _strategy, address _token) public checkStrategist{
        IGOFStrategy(_strategy).withdraw(_token);
    }

    function getExpectedReturn(address _strategy, address _token) public view returns (uint expected) {
        uint _balance = IERC20(_token).balanceOf(_strategy);
        address _want = IGOFStrategy(_strategy).getWant();
        // cal out amount
        address[] memory swap2TokenRouting;
        swap2TokenRouting[0] = _token;
        swap2TokenRouting[1] = wbnb;
        swap2TokenRouting[2] = _want;
        uint256[] memory amountsOut = ISwapRouter(onesplit).getAmountsOut(_balance, swap2TokenRouting);
        expected = amountsOut[swap2TokenRouting.length -1];
    }
    
    // Only allows to withdraw non-core strategy tokens ~ this is over and above normal yield
    function yearn(address _strategy, address _token) public checkStrategist{
        // This contract should never have value in it, but just incase since this is a public call
        uint _before = IERC20(_token).balanceOf(address(this));
        IGOFStrategy(_strategy).withdraw(_token);
        uint _after =  IERC20(_token).balanceOf(address(this));
        if (_after > _before) {
            uint _amount = _after.sub(_before);
            address _want = IGOFStrategy(_strategy).getWant();
            
            _before = IERC20(_want).balanceOf(address(this));
            IERC20(_token).safeApprove(onesplit, 0);
            IERC20(_token).safeApprove(onesplit, _amount);

            //swap by
            address[] memory swap2TokenRouting;
            swap2TokenRouting[0] = _token;
            swap2TokenRouting[1] = wbnb;
            swap2TokenRouting[2] = _want;
            ISwapRouter(onesplit).swapExactTokensForTokens(_amount, 0, swap2TokenRouting, address(this), now.add(1800)); 
            
            _after = IERC20(_want).balanceOf(address(this));
            if (_after > _before) {
                _amount = _after.sub(_before);
                uint _reward = _amount.mul(split).div(max);
                earn(_want, _amount.sub(_reward));
                IERC20(_want).safeTransfer(rewards, _reward);
            }
        }
    }
    
    function withdraw(address _token, uint _amount) public override {
        require(msg.sender == vaults[_token] || msg.sender == strategist, "Golff:!vault");
        IGOFStrategy(strategies[_token]).withdraw(_amount);
    }
}