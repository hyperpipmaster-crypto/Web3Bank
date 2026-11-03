// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract InterestBearingWeb3Bank {
    uint256 public constant INTEREST_RATE_BPS = 500; 
    uint256 public constant BPS_DIVISOR = 10000;
    uint256 public constant SECONDS_IN_YEAR = 31536000;

    address public contractOwner;

    struct Account {
        uint256 baseBalance;
        uint256 lastUpdatedTime;
    }

    mapping(address => Account) private bankAccounts;

    event DepositMade(address indexed accountAddress, uint256 amount, uint256 newTotalWithInterest);
    event WithdrawalMade(address indexed accountAddress, uint256 amount, uint256 remainingTotalWithInterest);
    event InterestPaid(address indexed accountAddress, uint256 interestEarned);

    error ZeroDepositNotAllowed();
    error InsufficientFunds(uint256 requested, uint256 available);
    error BankLiquidityDepleted();

    modifier onlyOwner() {
        require(msg.sender == contractOwner, "Only the bank owner can call this");
        _;
    }

    constructor() payable {
        contractOwner = msg.sender;
    }

    function _calculateInterest(address _user) internal view returns (uint256) {
        Account memory account = bankAccounts[_user];
        if (account.baseBalance == 0 || account.lastUpdatedTime == 0) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp - account.lastUpdatedTime;
        uint256 interestAccrued = (account.baseBalance * INTEREST_RATE_BPS * timeElapsed) / (BPS_DIVISOR * SECONDS_IN_YEAR);
        
        return interestAccrued;
    }

    function _applyAccruedInterest(address _user) private {
        uint256 interest = _calculateInterest(_user);
        
        if (interest > 0) {
            bankAccounts[_user].baseBalance += interest;
            emit InterestPaid(_user, interest);
        }
        
        bankAccounts[_user].lastUpdatedTime = block.timestamp;
    }

    function deposit() public payable {
        if (msg.value == 0) {
            revert ZeroDepositNotAllowed();
        }

        _applyAccruedInterest(msg.sender);

        bankAccounts[msg.sender].baseBalance += msg.value;

        emit DepositMade(msg.sender, msg.value, bankAccounts[msg.sender].baseBalance);
    }

    function withdraw(uint256 _amount) public {
        _applyAccruedInterest(msg.sender);

        uint256 overallAvailable = bankAccounts[msg.sender].baseBalance;
        if (_amount > overallAvailable) {
            revert InsufficientFunds(_amount, overallAvailable);
        }

        if (address(this).balance < _amount) {
            revert BankLiquidityDepleted();
        }

        bankAccounts[msg.sender].baseBalance -= _amount;

        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Ether transfer failed");

        emit WithdrawalMade(msg.sender, _amount, bankAccounts[msg.sender].baseBalance);
    }

    function checkLiveBalance(address _user) public view returns (uint256) {
        uint256 pendingInterest = _calculateInterest(_user);
        return bankAccounts[_user].baseBalance + pendingInterest;
    }

    function fundBankLiquidity() public payable onlyOwner {}

    function getBankTotalLiquidity() public view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {
        deposit();
    }
}
