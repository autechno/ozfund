 // SPDX-License-Identifier: auTech;
pragma solidity ^0.8.7;

import "library/SafeMath.sol";
import "library/BEP20.sol";

struct Permit {
    address owner;
    address spender;
    uint256 value;
    uint256 nonce;
    uint256 deadline;
}



interface IOZCoin is IBEP20 {

    function permitApprove(Permit memory permit, uint8 v, bytes32 r, bytes32 s) external;
}

interface IToto is IBEP20 {

    function dayProduction4Stake(uint dayNum) external returns (uint);

    function transferStakePool(address spender,uint amount) external;

}

contract OZCoinStake {
        
    using SafeMath for uint;

    struct Account {
        address accountAddress;
        uint256 accountSerialNumber;
        uint256 stakeAmount;
        uint256 beginStakeTimestamp;
        uint256 stakeExpirationTimestamp;
        uint256 stakeExpirationSettleCount;
        uint256 totoAmount;
    }


    uint public totalStake;

    address private contractOwner;

    uint lastSettleTime;

    uint initialTime;

    uint settleCycle = 3;

    //结算次数 
    uint public settleCount;

    //地址-序列号加入时结算次数
    mapping(address => mapping(uint => uint)) public  openAccountCount;

    //根据加入时次数分组
    mapping(uint => Account[]) public countAccounts;

    //地址下面账户序列号
    mapping(address => uint[]) public accountAddressSerialNumber;

    //每次结算时总质押数量
    mapping(uint => uint) public countTotalStakeAmount;

    //每次的质押量
    mapping(uint => uint) public countStakeAmount;

    //结算次数-ozcoin对toto收益比例
    mapping(uint => uint) public countYield;

    //对应次数-地址-序列号-地址下标
    mapping(uint => mapping(address => mapping(uint => uint))) addressIds;

    //地址-序列号-地址序列号数组下标
    mapping(address => mapping(uint => uint)) serialNumberIndex;

    //地址-质押序列号 递增
    mapping (address => uint) public accountSerialNumber;

    //天数-是否结算
    mapping (uint => bool) public ifDaySettle;

    address OZCAddress;

    address multiSignWallet;

    event AccountStakeExpirationTimestampChange(address accountAddress, uint serialNumber, uint beforeValue, uint afterValue);

    modifier onlyMultiSign() {
        require(msg.sender == multiSignWallet,"Forbidden");
        _;
    }

    function withdrawToken(address contractAddress,address targetAddress,uint amount) onlyMultiSign external {
        IBEP20(contractAddress).transfer(targetAddress,amount);
    }

    function getAllAccountByAddress(address accountAddress) public view returns (uint,uint) {
        uint accountNum = 0;
        uint totalStakeAmount = 0;
        for (uint i = 0 ; i < accountAddressSerialNumber[accountAddress].length ; i++) {
            uint serialNumber = accountAddressSerialNumber[accountAddress][i];
            uint openSettleCount = openAccountCount[accountAddress][serialNumber];
            uint index = addressIds[openSettleCount][accountAddress][serialNumber];
            totalStakeAmount = totalStakeAmount.add(countAccounts[openSettleCount][index].stakeAmount);
            accountNum = accountNum.add(1);
        }
        return (accountNum,totalStakeAmount);
    }

    function getAccountByAddress(address accountAddress,uint serialNumber) public view returns (Account memory) {
        uint openSettleCount = openAccountCount[accountAddress][serialNumber];
        uint index = addressIds[openSettleCount][accountAddress][serialNumber];
        require(index > 0,"Nonexistent");
        return countAccounts[openSettleCount][index];
    }

    function openAccount(address accountAddress,uint stakeAmount) private returns (bool) {
        uint serialNumber = accountSerialNumber[accountAddress].add(1);
        accountSerialNumber[accountAddress] = serialNumber;
        uint nowTimestamp = block.timestamp;
        uint firstSettleTimestamp = nowTimestamp + (1 days - (nowTimestamp % 1 days)) + 2 hours;
        uint expirationTimestamp = firstSettleTimestamp + ((settleCycle-1) * 1 days);
        if (!ifDaySettle[nowTimestamp/1 days]) { //如果今天尚未结算 参与今日结算 过期时间-1天
            expirationTimestamp = expirationTimestamp - 1 days;
        }
        Account memory newAccount = Account(accountAddress,serialNumber,stakeAmount,nowTimestamp,expirationTimestamp,settleCount+settleCycle,0);
        if (countAccounts[settleCount].length==0) {
            countAccounts[settleCount].push();//0被占位
        }
        countAccounts[settleCount].push(newAccount);
        accountAddressSerialNumber[accountAddress].push(serialNumber);
        serialNumberIndex[accountAddress][serialNumber] = accountAddressSerialNumber[accountAddress].length - 1;
        addressIds[settleCount][accountAddress][serialNumber] = countAccounts[settleCount].length - 1;
        openAccountCount[accountAddress][serialNumber] = settleCount;
        totalStake = totalStake.add(stakeAmount);
        countStakeAmount[settleCount] = countStakeAmount[settleCount].add(stakeAmount);
        return true;
    }

    function removeStakeAccount(uint count,uint index) private {
        countAccounts[count][index] = countAccounts[count][countAccounts[count].length - 1];
        countAccounts[count].pop();
        if (countAccounts[count].length==1) {
            delete countAccounts[count];
        }
    }

    function removeStakeAccountSerialNumber(address accountAddress,uint serialNumber) private {
        uint index = serialNumberIndex[accountAddress][serialNumber];
        accountAddressSerialNumber[accountAddress][index] = accountAddressSerialNumber[accountAddress][accountAddressSerialNumber[accountAddress].length - 1];
        accountAddressSerialNumber[accountAddress].pop();
    }

    function removeStakeAccountByAddress(address accountAddress,uint serialNumber) private {
        uint openSettleCount = openAccountCount[accountAddress][serialNumber];
        uint index = addressIds[openSettleCount][accountAddress][serialNumber];
        delete countAccounts[openSettleCount][index]; //删除账户
        delete openAccountCount[accountAddress][serialNumber]; //删除账户对应的次数
        delete addressIds[openSettleCount][accountAddress][serialNumber]; //删除账户对应下标
        removeStakeAccountSerialNumber(accountAddress,serialNumber);//删除账户对应序列号
        removeStakeAccount(openSettleCount,index);
    }

    function updateStakeAccountByAddress(Account memory updateAccount) private {
        uint openSettleCount = openAccountCount[updateAccount.accountAddress][updateAccount.accountSerialNumber];
        uint index = addressIds[openSettleCount][updateAccount.accountAddress][updateAccount.accountSerialNumber];
        delete countAccounts[openSettleCount][index]; //删除账户
        countAccounts[openSettleCount][index] = updateAccount;
    }

    function simulationRedemption() external  view returns (uint,uint) {
        address accountAddress = msg.sender;
        uint accountNum = 0;
        uint sumToto = 0;
        for (uint i = 0 ; i < accountAddressSerialNumber[accountAddress].length ; i++) {
            accountNum = accountNum.add(1);
            uint serialNumber = accountAddressSerialNumber[accountAddress][i];
            uint openSettleCount = openAccountCount[accountAddress][serialNumber];
            Account memory account = getAccountByAddress(accountAddress,serialNumber);
            if(account.stakeExpirationSettleCount > settleCount) {
                continue;
            }
            //周期为开户后30次  ex:0次进入 结算1-30 ; 31次进入 结算32-61次
            uint addCount = 0;
            for (uint si = openSettleCount + 1 ; si <= account.stakeExpirationSettleCount ; si++) {
                uint yield = countYield[si];
                account.totoAmount = account.totoAmount.add(yield.mul(account.stakeAmount));//质押数量计算每次收益
                addCount = addCount.add(1);
            }
            sumToto = sumToto.add(account.totoAmount);
        }

        return (accountNum,sumToto);
    }

    function redemption() external returns (bool) {
        address accountAddress = msg.sender;
        for (uint i = 0 ; i < accountAddressSerialNumber[accountAddress].length ; i++) {
            uint serialNumber = accountAddressSerialNumber[accountAddress][i];
            uint openSettleCount = openAccountCount[accountAddress][serialNumber];
            Account memory account = getAccountByAddress(accountAddress,serialNumber);
            if(account.stakeExpirationSettleCount > settleCount) {
                continue;
            }
            for (uint si = openSettleCount + 1 ; si <= account.stakeExpirationSettleCount ; si++) {
                uint yield = countYield[si];
                account.totoAmount = account.totoAmount.add(yield.mul(account.stakeAmount));//质押数量计算每次收益
            }
            //返还ozcoin  派发toto
            IOZCoin(OZCAddress).transfer(accountAddress,account.stakeAmount);
            IToto(contractOwner).transferStakePool(accountAddress,account.totoAmount);
            removeStakeAccountByAddress(accountAddress,serialNumber);
        }
        return true;
    }


    function changeAccountStakeExpirationTimestamp(address accountAddress) onlyMultiSign external returns (bool) {
        for (uint i = 0 ; i < accountAddressSerialNumber[accountAddress].length ; i++) {
            uint serialNumber = accountAddressSerialNumber[accountAddress][i];
            Account memory account = getAccountByAddress(accountAddress,serialNumber);
            if(account.stakeExpirationSettleCount <= settleCount) {
                continue;
            }
            uint openSettleCount = openAccountCount[accountAddress][serialNumber];
            uint before = account.stakeExpirationTimestamp;
            uint timestamp = block.timestamp;
            account.stakeExpirationTimestamp = timestamp;
            account.stakeExpirationSettleCount = settleCount;
            updateStakeAccountByAddress(account);
            countStakeAmount[openSettleCount] = countStakeAmount[openSettleCount].sub(account.stakeAmount);
            totalStake = totalStake.sub(account.stakeAmount);
            emit AccountStakeExpirationTimestampChange(accountAddress, serialNumber, before, timestamp);

        }
        return true;
    }

    function stake(uint amount,uint nonce,uint deadline,uint8 v, bytes32 r, bytes32 s) external returns (bool success) {
        address from = msg.sender;
        address to = address(this);
        Permit memory permit = Permit(from,to,amount,nonce,deadline);
        IOZCoin(OZCAddress).permitApprove(permit,v,r,s);
        IOZCoin(OZCAddress).transferFrom(from,to,amount);
        openAccount(from,amount);
        return true;
    }

    function settle(uint timestamp) external {
        address _sender = msg.sender;
        require(_sender == contractOwner,"Not my owner");
        require( timestamp < block.timestamp,'exception call');
        require( timestamp > initialTime,'exception call');
        require( timestamp - lastSettleTime >= 1 days,'In the cooling');
        require(!ifDaySettle[timestamp/1 days],'Repeat settle');
        uint totoProduction = IToto(_sender).dayProduction4Stake(timestamp/1 days);
        settleCount = settleCount.add(1);
        if (settleCount>settleCycle) {//剔除掉周期之外保存的总量
            uint expirtionCount = settleCount - settleCycle - 1; //例如:第四次结算 总量为1 2 3质押量 去除0次
            totalStake =  totalStake.sub(countStakeAmount[expirtionCount]);
        }
        ifDaySettle[timestamp/1 days] = true;
        uint ozcoinYield = 0;
        countTotalStakeAmount[settleCount] = totalStake;
        if (totalStake>0) {
            ozcoinYield = totoProduction.div(totalStake);
        }
        countYield[settleCount] = ozcoinYield;
        lastSettleTime = timestamp;
    }


    constructor (address ozcContractAddress,address multiSignWalletAddress,uint initialTimeStamp) {
        contractOwner = msg.sender;
        initialTime = initialTimeStamp;
        OZCAddress = ozcContractAddress;
        multiSignWallet = multiSignWalletAddress;
    }
    
}