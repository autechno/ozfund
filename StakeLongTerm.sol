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

contract OZCoinLongTermStake {

    using SafeMath for uint;

    struct StakeRecord{
        address accountAddress;//
        uint ozcStakeAmount;//质押额
        uint stakeTime;//质押时间 精确到天
        uint lockInPeriod;
        uint expectedTime;//预计到期时间 精确到天
        uint totoIncomeAmount;//收益
    }

    address private contractOwner;//所有者
    uint private lockInPeriod = 365 * 3 * 1 days;

    uint public ozcTotalInStockAmount;//总质押余额

    mapping(address => StakeRecord[]) public stakeAccounts;//质押账户
    address[] public accountKeys;

    mapping(address => StakeRecord[]) public freedomAccounts;//质押到期的

    // uint256 public lastSettleTime;//最后一次执行settle时间戳
    uint256 public lastSettlePeriod;//最后一次执行settle的周期数

    address private OZCAddress;
    address private multiSignWallet;
    address private TotoAddress;

    event AccountStakeExpirationTimestampChange(address accountAddress, uint serialNumber, uint beforeValue, uint afterValue);

    modifier onlyMultiSign() {
        require(msg.sender == multiSignWallet,"Forbidden");
        _;
    }

    function withdrawToken(address contractAddress,address targetAddress,uint amount) onlyMultiSign public {
        IERC20(contractAddress).transfer(targetAddress,amount);
    }

    function getAccountByAddress(address accountAddress) public view returns (StakeRecord[] memory) {
        StakeRecord[] memory records = stakeAccounts[accountAddress];
        require(records.length > 0,"Nonexistent");
        return records;
    }

    //质押
    function stake(address from,uint amount,uint nonce,uint deadline,uint8 v, bytes32 r, bytes32 s) external returns (bool success) {
        address to = address(this);
        Common.Permit memory permit = Common.Permit(from,to,amount,nonce,deadline);
        IOZCoin(OZCAddress).permitApprove(permit,v,r,s);
        IOZCoin(OZCAddress).transferFrom(from,to,amount);
        openAccount(from,amount);
        return true;
    }

    function openAccount(address accountAddress,uint stakeAmount) private returns (bool) {
        uint stakeTime = block.timestamp / 1 days;
        uint expectedTime = stakeTime + lockInPeriod;
        StakeRecord[] memory _accountRecords = stakeAccounts[accountAddress];
        if (_accountRecords.length == 0) {
            accountKeys.push(accountAddress);
        }
        stakeAccounts[accountAddress].push(StakeRecord(accountAddress,stakeAmount,stakeTime, lockInPeriod, expectedTime, 0));
        ozcTotalInStockAmount = ozcTotalInStockAmount + stakeAmount;
        return true;
    }

    //结算收益,没天生产完toto后计算收益 如果没有质押的 则销毁矿池发的
    function settle() external {
        require(msg.sender == contractOwner,"Not my owner");
        uint timestamp = block.timestamp;
        uint settlePeriod = getSettlePeriod(timestamp);
        require(settlePeriod > lastSettlePeriod,'In the cooling');//比上次执行时间大于1个周期
        // require(ozcTotalInStockAmount > 0,"stake empty");

        if(ozcTotalInStockAmount == 0) {
            //说明没有当前没有质押的币，需要将当前toto质押矿池清空
            IToto(TotoAddress).burnPool(Common.PoolId.OzSupporterPool);
            return;
        }
        
        uint totoPeriod = IToto(TotoAddress).getPeriod(timestamp);
        uint totoProduction = IToto(TotoAddress).getPoolProductinByPeriod(totoPeriod-1,Common.PoolId.OzSupporterPool);//取质押矿池新增toto 上一个时段的

        uint keyCount = accountKeys.length;
        for (uint i = keyCount - 1; i >= 0; i--) {
            StakeRecord[] storage _accountRecords = stakeAccounts[accountKeys[i]];
            uint _counts = _accountRecords.length;
            for (uint j = _counts - 1; j >= 0; j --) {
                StakeRecord storage record = _accountRecords[j];
                uint _amount = record.ozcStakeAmount;
                uint _income = totoProduction * ((_amount * 10000) / ozcTotalInStockAmount) / 10000; //精度问题 缩放因子
                record.totoIncomeAmount += _income;

                //是否已到期
                if (timestamp >= record.expectedTime) {
                    //转入到期池，或继续质押或自动转出或放到到期池不动
                    transToFreedom(record);
                    //redemptionAuto(record);
                    ozcTotalInStockAmount -= record.ozcStakeAmount;//减总余额
                    _accountRecords[j] = _accountRecords[_accountRecords.length-1];
                    _accountRecords.pop();
                    if (_accountRecords.length == 0) {
                        //删除账户
                        delete stakeAccounts[accountKeys[i]];
                        accountKeys[i] = accountKeys[accountKeys.length - 1];
                        accountKeys.pop();
                    }
                }
            }
        }
        lastSettlePeriod = settlePeriod;
    }

    function getSettlePeriod(uint timestamp) private pure returns (uint) {
        return timestamp / 1 days;
    }

    //转入freedom中 不动
    function transToFreedom(StakeRecord memory record) private {
        StakeRecord[] storage _fRecords = freedomAccounts[record.accountAddress];
        _fRecords.push(record);
    }

    //自动转到客户钱包地址
    function redemptionAuto(StakeRecord memory record) private {
        address accountAddress = record.accountAddress;
        IOZCoin(OZCAddress).transfer(accountAddress,record.ozcStakeAmount);
        IToto(TotoAddress).transferStakePool(Common.PoolId.OzSupporterPool, accountAddress,record.totoIncomeAmount);
    }

    //手动赎回，从freedom中一次性提取
    function redemption() external returns (bool) {
        address accountAddress = msg.sender;
        StakeRecord[] storage records = freedomAccounts[accountAddress];
        require(records.length > 0,"None freedom stakes.");

        for (uint i = 0; i < records.length; i++) {
            StakeRecord memory _item = records[i];
            IOZCoin(OZCAddress).transfer(accountAddress,_item.ozcStakeAmount);
            IToto(TotoAddress).transferStakePool(Common.PoolId.OzSupporterPool, accountAddress, _item.totoIncomeAmount);
        }
        delete freedomAccounts[accountAddress];
        return true;
    }

    constructor (address multiSignWalletAddress,address ozcContractAddress,address totoContractAddress) {
        contractOwner = msg.sender;
        multiSignWallet = multiSignWalletAddress;
        OZCAddress = ozcContractAddress;
        TotoAddress = totoContractAddress;
        // lastSettleTime = block.timestamp;
    }

}