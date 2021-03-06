pragma solidity ^0.5.7;
pragma experimental ABIEncoderV2;


import '@studydefi/money-legos/dydx/contracts/DydxFlashloanBase.sol';
import '@studydefi/money-legos/dydx/contracts/ICallee.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './Compound.sol';


contract YieldFarmer is ICallee, DydxFlashloanBase {

  address public owner;

  enum Direction { Deposit, Withdraw  }
  struct Operation {
    address   token;
    address   cToken;
    Direction direction;
    uint      amountProvided;
    uint      amountBorrowed;
  }

  constrcutor() {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    require(msg.sender == owner, "Only owner");
  }

  function openPosition(
    address _solo,
    address _token,
    address  _cToken,
    uint    _amountProvided,
    uint    _amountBorrowed
  ) external onlyOwner() {
    _initiateFlashloan(
      _solo,
      _token,
      _cToken,
      Direction.Deposit,
      _amountProvided - 2,
      _amountBorrowed
    );

  }

  function closePosition(address _solo, address _token, address  _cToken) external onlyOwner() {
    IERC20(_token).transferFrom(msg.sender, address(this), 2);
    claimComp();
    uint borrowBalance = getBorrowBalance(_cToken);
    _initiateFlashloan(_solo, _token, _cToken, Direction.Withdraw, 0, borrowBalance);

    address compAddress = getCompAddress();
    IERC20 comp         = IERC20(compAddress);
    uint compBalance    = comp.balanceOf(address(this));
    comp.transfer(msg.sender, compBalance);

    IERC20 token      = IERC20(_token);
    uint tokenBalance = token.balanceOf(address(this));
    token.transfer(msg.sender, tokenBalance);

  }

  // Naming convention used by studyDefi lib
  function callFunction( address sender, Account.info memory account, bytes memory data) public {
    Operation memory operation = abi.decode(data,(Operation));

    if (operation.direction == Direction.Deposit) {
      supply(operation.cToken, operation.amountProvided + operation.amountBorrowed);
      enterMarket(operation.cToken);
      borrow(operation.cToken, operation.borrowedAmount);
    } else {
      repayBorrow(operation.cToken, operation.amountBorrowed);
      uint cTokenBalance = getcTokenBalance(operation.cToken);
      redeem(operation.cToken, cTokenBalance);
    }
  }


  function _initiateFlashloan(
      address   _solo,
      address   _token,
      address   _cToken,
      Direction _direction,
      uint      _amountProvided,
      uint      _amountBorrowed
    ) internal {
      ISoloMargin solo    = ISoloMargin(_solo);
      uint256 marketId    = _getMarketIdFromTokenAddress(_solo, _token);
      uint256 repayAmount = _getRepaymentAmountInternal(_amountBorrowed);

      IERC20(_token).approve(_solo, repayAmount);

      // 1. Withdraw $
      // 2. Call callFunction(...)
      // 3. Deposit back $
      Actions.ActionArgs[] memory operations = new Actions.ActionArgs[](3);

      operations[0] = _getWithdrawAction(marketId, _amountBorrowed);
      operations[1] = _getCallAction(
          // Encode MyCustomData for callFunction
          abi.encode(Operation({
            token: _token, 
            cToken: _cToken, 
            direction: _direction,
            amountProvided: _amountProvided, 
            amountBorrowed: _amountBorrowed
          }))
      );
      operations[2] = _getDepositAction(marketId, repayAmount);

      Account.Info[] memory accountInfos = new Account.Info[](1);
      accountInfos[0] = _getAccountInfo();

      solo.operate(accountInfos, operations);
    }

}
