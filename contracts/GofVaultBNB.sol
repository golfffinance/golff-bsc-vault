// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./interfaces/IGOFController.sol";
import "./interfaces/IGOFPool.sol";
import "./interfaces/IGOFVaultMigrateable.sol";
import "./interfaces/IWBNB.sol";


contract GOFVaultBNB is ERC20, Ownable, IGOFVaultMigrateable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    struct UserInfo {
        uint256 deposit;
        uint256 withdraw;
        uint256 netDeposit;
    }

    IERC20 public token;

    uint public min = 10000;
    uint public constant max = 10000;
    uint public earnLowerlimit = 0;

    address public controller;
    address public gofPool;

    uint256 public totalDeposit;
    uint256 public totalWithdraw;

    IGOFVaultMigrateable public newVault;

    mapping(address => UserInfo) public userInfo;

    event Deposit(address payer, address account, uint256 amount);
    event Withdraw(address account, uint256 amount);
    event Migrate(address account, address newVault, uint256 amount);

    constructor (address _token, address _controller) 
    public ERC20(
        string(abi.encodePacked("Golff ", ERC20(_token).name())),
        "G-BSCBNB"
    ) {
        token = IERC20(_token);
        controller = _controller;
        _setupDecimals(ERC20(_token).decimals());
    }

    function stakeToken() external view returns (address) {
        return address(token);
    }

    function balance() public view returns (uint) {
        return token.balanceOf(address(this))
                .add(IGOFController(controller).balanceOf(address(token)));
    }

    function setMin(uint _min) external onlyOwner{
        min = _min;
    }

    function setController(address _controller) external onlyOwner{
        controller = _controller;
    }
    function setEarnLowerlimit(uint256 _earnLowerlimit) external onlyOwner{
      earnLowerlimit = _earnLowerlimit;
    }

    function available() public view returns (uint) {
        return token.balanceOf(address(this)).mul(min).div(max);
    }

    function earn() public {
        uint _bal = available();
        token.safeTransfer(controller, _bal);
        IGOFController(controller).earn(address(token), _bal);
    }

    function depositAll() external {
        deposit(token.balanceOf(msg.sender));
    }

    function deposit(uint _amount) public {
        _amount = transferErc20In(_amount);
        depositInternal(msg.sender, _amount, false);
    }

    function depositAndFarm(uint _amount) public {
        _amount = transferErc20In(_amount);
        depositInternal(msg.sender, _amount, true);
    }

    function depositAllAndFarm() external {
        depositAndFarm(token.balanceOf(msg.sender));
    }

    function transferErc20In(uint _amount) internal returns(uint){
        uint _before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint _after = token.balanceOf(address(this));
        _amount = _after.sub(_before);
        return _amount;
    }

    function depositBNB() public payable {
        uint _before = token.balanceOf(address(this));
        uint _amount = msg.value;
        IWBNB(address(token)).deposit{value:_amount}();//.value(_amount)();
        uint _after = token.balanceOf(address(this));
        _amount = _after.sub(_before);
        depositInternal(msg.sender, _amount, false);
    }

    function depositBNBAndFarm() public payable {
        uint _before = token.balanceOf(address(this));
        uint _amount = msg.value;
        IWBNB(address(token)).deposit{value:_amount}();//.value(_amount)();
        uint _after = token.balanceOf(address(this));
        _amount = _after.sub(_before);
        depositInternal(msg.sender, _amount, true);
    }

    function depositBehalf(address _account, uint _amount) public override{
        _amount = transferErc20In(_amount);
        depositInternal(_account, _amount, false);
    }

    function depositInternal(address _account, uint _amount, bool _autoFarm) internal {
        uint _pool = balance();
        uint _shares = 0;
        if (totalSupply() == 0) {
            _shares = _amount;
        } else {
            _shares = (_amount.mul(totalSupply())).div(_pool);
        }
        
        if (gofPool != address(0) && _autoFarm) {
            _mint(address(this), _shares);
            IERC20(address(this)).safeApprove(gofPool, _shares);
            IGOFPool(gofPool).stakeBehalf(_account, _shares);
        } else {
            _mint(_account, _shares);
        }

        UserInfo storage user = userInfo[_account];
        user.deposit = user.deposit.add(_amount);
        user.netDeposit = user.netDeposit.add(_amount);

        totalDeposit = totalDeposit.add(_amount);

        if (token.balanceOf(address(this))>earnLowerlimit){
          earn();
        }

        emit Deposit(msg.sender, _account, _amount);
    }

    function withdrawFromController(uint _shares) internal returns (uint){
        uint r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);
        
        uint b = token.balanceOf(address(this));
        if (b < r) {
            uint _withdraw = r.sub(b);
            IGOFController(controller).withdraw(address(token), _withdraw);
            uint _after = token.balanceOf(address(this));
            uint _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }

        return r;
    }

    function logWithdraw(address _account, uint _amount) internal {
        UserInfo storage user = userInfo[_account];
        user.withdraw = user.withdraw.add(_amount);
        if (user.netDeposit > _amount) {
            user.netDeposit = user.netDeposit.sub(_amount);
        } else {
            user.netDeposit = 0;
        }

        totalWithdraw = totalWithdraw.add(_amount);

        emit Withdraw(msg.sender, _amount);
    }

    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    function withdrawAllBNB() external {
        withdrawBNB(balanceOf(msg.sender));
    }

    function withdraw(uint _shares) public {
        require(_shares > 0, 'Cannot withdraw 0');
        uint r = withdrawFromController(_shares);
        token.safeTransfer(msg.sender, r);
        logWithdraw(msg.sender, r);
    }

    function withdrawBNB(uint _shares) public{
        require(_shares > 0, 'Cannot withdraw 0');
        uint r = withdrawFromController(_shares);
        IWBNB(address(token)).withdraw(r);
        address(uint160(msg.sender)).transfer(r);
        logWithdraw(msg.sender, r);
    }

    function accrueReward(address _account) public view returns (uint) {
        UserInfo memory user = userInfo[_account];
        uint gb = balanceOf(_account);
        if (gofPool != address(0)) {
            gb = gb.add(IGOFPool(gofPool).balanceOf(_account));
        }
        uint amount = 0;
        uint total = totalSupply();
        if (total > 0) {
            amount = (balance().mul(gb)).div(total);
        }
        uint _wb = user.withdraw.add(amount);
        if (_wb < user.deposit) {
            return 0;
        } else {
            return _wb.sub(user.deposit);
        }
    }

    function migrate() external override {
        require(address(newVault) != address(0), "No new vault");
        uint _shares = balanceOf(msg.sender);
        uint _amount = withdrawFromController(_shares);
        token.safeApprove(address(newVault), _amount);
        newVault.depositBehalf(msg.sender, _amount);

        logWithdraw(msg.sender, _amount);

        emit Migrate(msg.sender, address(newVault), _amount);
    }

    function setMigrateDist(IGOFVaultMigrateable _newVault) external override onlyOwner {
        require(address(this) != address(_newVault), "Not self");
        newVault = _newVault;
    }

    function setGofPool(address _gofPool) external onlyOwner {
        require(address(this) != gofPool, "Not self");
        gofPool = _gofPool;
    }

    function getPricePerFullShare() public view returns (uint) {
        return balance().mul(1e18).div(totalSupply());
    }
    
    receive() external payable {
        if (msg.sender != address(token)) {
            depositBNB();
        }
    }
}