// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./library/SafeMath.sol";
import "./library/IERC20.sol";
import {Common} from "./library/Common.sol";

interface IOZCoin is IERC20 {
    function permitApprove(Common.Permit memory permit, uint8 v, bytes32 r, bytes32 s) external;
}

interface IToto is IERC20 {
    function getPeriod(uint timestamp) external view returns (uint);
    function getPoolProductinByPeriod(uint period, Common.PoolId poolId) external view returns (uint);
    function transferStakePool(Common.PoolId poolId, address spender, uint amount) external;
    function burnPool(Common.PoolId poolId) external returns (bool);
}

contract OZCoinDemandStake {

    using SafeMath for uint;

    struct Account {
        address accountAddress;//账户地址
        uint256 ozcInStockAmount;//已入库总质押ozc余额
        uint256 ozcInTransitAmount;//在途质押ozc余额
        uint256 totoIncomeAmount;//toto收益余额
        uint stakeDays;//质押结算天数
        uint firstStakeTimestamp;//初次质押时间戳
    }

    address private contractOwner;//所有者

    uint public ozcTotalInStockAmount;//总质押余额

    mapping(address => Account) public stakeAccounts;//质押账户
    address[] public accountKeys;

    uint256 public lastSettlePeriod;//最后一次执行settle的周期数

    address private OZCAddress;
    address private multiSignWallet;
    address private TotoAddress;

//    event AccountStakeExpirationTimestampChange(address accountAddress, uint serialNumber, uint beforeValue, uint afterValue);

    modifier onlyMultiSign() {
        require(msg.sender == multiSignWallet,"Forbidden");
        _;
    }

    function withdrawToken(address contractAddress,address targetAddress,uint amount) onlyMultiSign public {
        IERC20(contractAddress).transfer(targetAddress,amount);
    }

    function getAccountByAddress(address accountAddress) public view returns (Account memory) {
        Account memory _account = stakeAccounts[accountAddress];
        require(_account.accountAddress != address(0),"Nonexistent");
        return _account;
    }

    //赎回，优先赎回在途币 在途币不计息，然后赎回已入库的币 以及提息
    function redemption(address accountAddress, uint amount) external returns (bool) {
//        address accountAddress = msg.sender;
        Account storage _account = stakeAccounts[accountAddress];
        require(_account.accountAddress != address(0),"Nonexistent");
        require(amount > 0 && amount <= _account.ozcInTransitAmount + _account.ozcInStockAmount,"Insufficient balance");

        //返还ozc
        //先在途部分
        uint _amount = amount;
        if (_account.ozcInTransitAmount > amount) {
            _amount = amount;
        } else {
            _amount = _account.ozcInTransitAmount;
        }
        IOZCoin(OZCAddress).transfer(accountAddress,_amount);
        _account.ozcInTransitAmount = _account.ozcInTransitAmount.sub(_amount);//扣减在途
        //再已入库部分，并提息
        _amount = amount - _amount;
        if (_amount > 0) {
            IOZCoin(OZCAddress).transfer(accountAddress,_amount);

            uint _totoAmount = _account.totoIncomeAmount * ((_amount * 10000) / _account.ozcInStockAmount) / 10000; //精度问题 缩放因子
            IToto(TotoAddress).transferStakePool(Common.PoolId.StakePool, accountAddress, _totoAmount);

            //扣减资产
            _account.ozcInStockAmount = _account.ozcInStockAmount.sub(_amount);
            _account.totoIncomeAmount = _account.totoIncomeAmount.sub(_totoAmount);
            ozcTotalInStockAmount = ozcTotalInStockAmount.sub(_amount);
        }
        return true;
    }

    //质押
    function stake(uint amount,uint nonce,uint deadline, uint8 v, bytes32 r, bytes32 s) external returns (bool success) {
        address from = msg.sender;
        address to = address(this);
        Common.Permit memory permit = Common.Permit(from,to,amount,nonce,deadline);
        IOZCoin(OZCAddress).permitApprove(permit,v,r,s);
        IOZCoin(OZCAddress).transferFrom(from,to,amount);
        openAccount(from,amount);
        return true;
    }

    function openAccount(address accountAddress,uint stakeAmount) private returns (bool) {
        Account storage _account = stakeAccounts[accountAddress];
        if(_account.accountAddress != address(0)) {
            _account.ozcInTransitAmount = _account.ozcInTransitAmount.add(stakeAmount);
        } else {
            uint nowTimestamp = block.timestamp;
            stakeAccounts[accountAddress] = Account(accountAddress,0,stakeAmount,0,0,nowTimestamp);
            accountKeys.push(accountAddress);
        }
        return true;
    }

    //确认 将在途币 滚入总额计息币
    function confirm() external returns (bool) {
        require(msg.sender == contractOwner,"Not my owner");
        uint keyCount = accountKeys.length;
        for (uint i = keyCount - 1; i >= 0; i--) {
            Account storage _account = stakeAccounts[accountKeys[i]];
            _account.ozcInStockAmount = _account.ozcInStockAmount.add(_account.ozcInTransitAmount);
            ozcTotalInStockAmount = ozcTotalInStockAmount.add(_account.ozcInTransitAmount);
            _account.ozcInTransitAmount = 0;

            if (_account.ozcInStockAmount == 0) {
                //删除账户
                delete stakeAccounts[accountKeys[i]];
                accountKeys[i] = accountKeys[accountKeys.length - 1];
                accountKeys.pop();
            }
        }

        if(ozcTotalInStockAmount == 0) {
            //说明没有当前没有质押的币，需要将当前toto质押矿池清空
            IToto(TotoAddress).burnPool(Common.PoolId.StakePool);
        }

        return true;
    }

    //结算收益,没天生产完toto后计算收益 如果没有质押的 则销毁矿池发的
    function settle(uint timestamp) external {
        require(msg.sender == contractOwner,"Not my owner");
        uint settlePeriod = getSettlePeriod(timestamp);
        require(settlePeriod > lastSettlePeriod,'In the cooling');//比上次执行时间大于1个周期
        require(ozcTotalInStockAmount > 0,"stake empty");
        uint totoPeriod = IToto(TotoAddress).getPeriod(timestamp);
        uint totoProduction = IToto(TotoAddress).getPoolProductinByPeriod(totoPeriod-1,Common.PoolId.StakePool);//取质押矿池新增toto 上一个时段的

        uint keyCount = accountKeys.length;
        for (uint i = keyCount - 1; i >= 0; i--) {
            Account storage _account = stakeAccounts[accountKeys[i]];
            uint _amount = _account.ozcInStockAmount;
            if( _amount > 0) {
                uint _income = totoProduction * ((_amount * 10000) / ozcTotalInStockAmount) / 10000; //精度问题 缩放因子
                _account.totoIncomeAmount = _account.totoIncomeAmount.add(_income);
            }
        }
        lastSettlePeriod = settlePeriod;
    }

    function getSettlePeriod(uint timestamp) private pure returns (uint) {
        return timestamp / 1 days;
    }

    constructor (address multiSignWalletAddress,address ozcContractAddress,address totoContractAddress) {
        contractOwner = msg.sender;
        multiSignWallet = multiSignWalletAddress;
        OZCAddress = ozcContractAddress;
        TotoAddress = totoContractAddress;
//        lastSettleTime = block.timestamp;
    }

}