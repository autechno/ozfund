// SPDX-License-Identifier: auTech;
pragma solidity ^0.8.7;

import "library/SafeMath.sol";
import "./OZCoinTotoStake.sol";


struct TransferInfo {
    address spender;
    uint256 amount;
}

contract Pool {

    uint public poolId;

    address private contractOwner;

    constructor (uint id) {
        contractOwner = msg.sender;
        poolId = id;
    }

    function withdraw(address contractAddress,address spender,uint amount) external {
        address _sender = msg.sender;
        require(_sender == contractOwner,"Not my owner");
        IBEP20(contractAddress).transfer(spender,amount);
    }

}

contract TotoToken {

    OZCoinStake public ozcoinStake;

    address private contractOwner;

    using SafeMath for uint;

    uint public initialTime;

    uint public lastProduceTime;

    uint public lastSettleTime;

    uint256 private _totalSupply;

    string public constant name = "Toto";

    string public constant symbol = "TOTO";

    uint8 public constant decimals = 18;

    uint public lastProduction;

    mapping(uint => uint) public dayProduction4Stake;

    uint public nextProduction;

    uint public productionLimit;

    bool public allowExchange = true;

    address private multiSignWallet;

    mapping(uint => Pool) public pools;

    mapping(uint => address) public poolAutoAddress;

    mapping(address => uint) private supportedContractAddress;

    mapping(address => uint) private balances;

    mapping(uint => uint) public daySold;

    mapping(uint => uint) private poolDistributeProportion;

    mapping (address => mapping (address => uint)) public _allowance;

    event ContractOwnerChange(address beforeAddress, address afterAddress);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed _owner, address indexed _spender, uint _value);

    event DecreaseApprove(address indexed _owner, address indexed _spender, uint _value);

    event NextProductionChange(uint beforeValue, uint afterValue);

    event PoolAutoAddressChange(address beforeValue, address afterValue);

    event ProductionLimitChange(uint beforeValue, uint afterValue);

    event PoolDistributeProportionChange(uint poolId, uint proportion);

    enum PoolId {
        Pass,
        OzGroupPool,
        OzSupporterPool,
        OzFoundationPool,
        StakePool,
        OzbetPool,
        OzbetVipPool
    }

    modifier onlyMultiSign() {
        require(msg.sender == multiSignWallet,"Forbidden");
        _;
    }

    function balanceOf(address _owner) external view returns (uint balance) {
        return balances[_owner];
    }

    function doTransfer(address _from, address _to, uint _value) private {
        require(_from != _to);
        uint fromBalance = balances[_from];
        uint toBalance = balances[_to];
        require(fromBalance >= _value, "Insufficient funds");
        balances[_from] = fromBalance.sub(_value);
        balances[_to] = toBalance.add(_value);
        emit Transfer(_from, _to, _value);
    }

    function doApprove(address owner,address _spender,uint _value) private {
        uint remaining = _allowance[owner][_spender];
        remaining = remaining.add(_value);
        _allowance[owner][_spender] = remaining;
        emit Approval(owner,_spender,_value);
    }

    function transfer(address _to, uint _value) external returns (bool success) {
        address _owner = msg.sender;
        doTransfer(_owner,_to,_value);
        return true;
    }

    function approve(address _spender, uint _value) external returns (bool success){
        address _sender = msg.sender;
        doApprove(_sender,_spender,_value);
        return true;
    }

    function decreaseApprove(address _spender, uint _value) external returns (bool success){
        address _sender = msg.sender;
        uint remaining = _allowance[_sender][_spender];
        remaining = remaining.sub(_value);
        _allowance[_sender][_spender] = remaining;
        emit DecreaseApprove(_sender,_spender,_value);
        return true;
    }

    function allowance(address _owner, address _spender) external view returns (uint remaining){
        return _allowance[_owner][_spender];
    }

    function transferFrom(address _from, address _to, uint _value) external returns (bool success){
        address _sender = msg.sender;
        uint remaining = _allowance[_from][_sender];
        require(_value <= remaining,"Insufficient remaining allowance");
        remaining = remaining.sub(_value);
        _allowance[_from][_sender] = remaining;
        doTransfer(_from, _to, _value);
        return true;
    }

    function withdrawToken(address contractAddress,address targetAddress,uint amount) onlyMultiSign external returns(bool) {
        IBEP20(contractAddress).transfer(targetAddress,amount);
        return true;
    }

    function totalSupply() external view returns (uint){
        return _totalSupply;
    }

    function mint(address spender,uint _value) onlyMultiSign external returns (bool success) {
        return _mint(_value,spender);
    }

    function _mint(uint _value,address spender) private returns (bool success) {
        address _from = 0x0000000000000000000000000000000000000000;
        balances[spender] = balances[spender].add(_value);
        _totalSupply = _totalSupply.add(_value);
        emit Transfer(_from, spender, _value);
        return true;
    }

    function getBlockTimestamp() public view returns (uint) {
        return block.timestamp;
    }

    function setProductionLimit(uint productionLimitV) onlyMultiSign public returns(bool) {
        uint before = productionLimit;
        productionLimit = productionLimitV;
        emit ProductionLimitChange(before,productionLimitV);
        return true;
    }

    function setPoolDistributeProportion(uint ozGroupProportion, uint ozSupportProportion, uint ozFundProportion, uint stakeProportion, uint ozbetProportion, uint ozbetVipProportion) onlyMultiSign public returns(bool) {
        require(ozGroupProportion + ozSupportProportion + ozFundProportion + stakeProportion + ozbetProportion + ozbetVipProportion == 100,"Sum must to be 100");
        poolDistributeProportion[1] = ozGroupProportion;
        emit PoolDistributeProportionChange(1,ozGroupProportion);
        poolDistributeProportion[2] = ozSupportProportion;
        emit PoolDistributeProportionChange(2,ozSupportProportion);
        poolDistributeProportion[3] = ozFundProportion;
        emit PoolDistributeProportionChange(3,ozFundProportion);
        poolDistributeProportion[4] = stakeProportion;
        emit PoolDistributeProportionChange(4,stakeProportion);
        poolDistributeProportion[5] = ozbetProportion;
        emit PoolDistributeProportionChange(5,ozbetProportion);
        poolDistributeProportion[6] = ozbetVipProportion;
        emit PoolDistributeProportionChange(6,ozbetVipProportion);
        return true;
    }

    function setPoolDistributeProportionPrivate(uint ozGroupProportion, uint ozSupportProportion, uint ozFundProportion, uint stakeProportion, uint ozbetProportion, uint ozbetVipProportion) private {
        require(ozGroupProportion + ozSupportProportion + ozFundProportion + stakeProportion + ozbetProportion + ozbetVipProportion == 100,"Sum must to be 100");
        poolDistributeProportion[1] = ozGroupProportion;
        poolDistributeProportion[2] = ozSupportProportion;
        poolDistributeProportion[3] = ozFundProportion;
        poolDistributeProportion[4] = stakeProportion;
        poolDistributeProportion[5] = ozbetProportion;
        poolDistributeProportion[6] = ozbetVipProportion;
    }

    function setContractOwner(address newOwner) onlyMultiSign external returns (bool) {
        address beforeAddress = contractOwner;
        contractOwner = newOwner;
        emit ContractOwnerChange(beforeAddress,newOwner);
        return true;
    }

    function produce(uint timestamp) external returns (bool) {
        require( msg.sender == contractOwner,"Not my owner");
        require( timestamp < block.timestamp,"Exception call : can not  after the block");
        require( timestamp > initialTime,"Exception call : can not be before the initial");
        require( timestamp - lastProduceTime >= 1 days,"In the cooling");
        require(( _totalSupply + nextProduction <= productionLimit) || productionLimit == 0 ,"Production Limit");
        uint onePercent = nextProduction.div(100);
        _mint(nextProduction,address(this));
        lastProduction = nextProduction;
        address ozGroupPoolAddress = address(pools[uint(PoolId.OzGroupPool)]);
        uint ozGroupPoolAmount = onePercent.mul(poolDistributeProportion[uint(PoolId.OzGroupPool)]);
        doTransfer(address(this),ozGroupPoolAddress,ozGroupPoolAmount);

        address ozSupporterPoolAddress = address(pools[uint(PoolId.OzSupporterPool)]);
        uint ozSupporterPoolAmount = onePercent.mul(poolDistributeProportion[uint(PoolId.OzSupporterPool)]);
        doTransfer(address(this),ozSupporterPoolAddress,ozSupporterPoolAmount);

        address ozFoundationPoolAddress = address(pools[uint(PoolId.OzFoundationPool)]);
        uint ozFoundationPoolAmount = onePercent.mul(poolDistributeProportion[uint(PoolId.OzFoundationPool)]);
        doTransfer(address(this),ozFoundationPoolAddress,ozFoundationPoolAmount);

        address stakePoolAddress = address(pools[uint(PoolId.StakePool)]);
        uint stakePoolAmount = onePercent.mul(poolDistributeProportion[uint(PoolId.StakePool)]);
        dayProduction4Stake[timestamp/1 days] = stakePoolAmount;
        doTransfer(address(this),stakePoolAddress,stakePoolAmount);

        address ozbetPoolAddress = address(pools[uint(PoolId.OzbetPool)]);
        uint ozbetPoolAmount = onePercent.mul(poolDistributeProportion[uint(PoolId.OzbetPool)]);
        doTransfer(address(this),ozbetPoolAddress,ozbetPoolAmount);

        address ozbetVipPoolAddress = address(pools[uint(PoolId.OzbetVipPool)]);
        uint ozbetVipPoolAmont = onePercent.mul(poolDistributeProportion[uint(PoolId.OzbetVipPool)]);
        doTransfer(address(this),ozbetVipPoolAddress,ozbetVipPoolAmont);
        uint minProduction = 1000000;
        if(nextProduction>minProduction.mul(decimals)) {
            nextProduction = onePercent.mul(99);
            emit DecreaseApprove(lastProduction,nextProduction);
        }
        lastProduceTime = timestamp;
        return true;
    }

    function getDays() public view returns (uint) {
        uint currentTime = block.timestamp;
        uint difference = currentTime.sub(initialTime);
        uint dayNum = difference/1 days;
        if (difference % 1 days > 0) {
            dayNum += 1;
        }
        return dayNum;
    }

    function switchExchange() external onlyMultiSign returns(bool)  {
        if (allowExchange) {
            allowExchange = false;
        } else {
            allowExchange = true;
        }
        return true;
    }

    //使用稳定币兑换TOTO
    function exchange(address spender,address contractAddress,uint amount) external {
        require(supportedContractAddress[contractAddress] == 1,"Don't support");
        require(allowExchange,"Not allow");
        uint dayNum = getDays();
        uint todaySold = daySold[dayNum];
        address owner = msg.sender;
        uint allowanceValue = IBEP20(contractAddress).allowance(owner,address(this));
        require(allowanceValue >= amount,"Insufficient allowance");
        bool res = IBEP20(contractAddress).transferFrom(owner,address(this),amount);
        require(res,"Transfer failed");
        uint8 erc20decimals = IBEP20(contractAddress).decimals();
        //proportion toto对应erc20比例
        //根据精度差距计算兑换数量
        uint totoAmount = amount;
        uint ten = 10;
        if (erc20decimals<decimals) {
            uint8 decimalsDifference = decimals - erc20decimals;
            uint proportion = ten.power(decimalsDifference);
            totoAmount = amount.mul(proportion);
        }
        if (erc20decimals>decimals) {
            uint8 decimalsDifference = erc20decimals - decimals;
            uint proportion = ten.power(decimalsDifference);
            totoAmount = amount.div(proportion);
        }
        totoAmount = totoAmount.mul(10);
        uint sellLimit = 10000;
        require( todaySold + totoAmount <= sellLimit.mul(ten.power(decimals)),"Inadequate");
        _mint(totoAmount,spender);
        daySold[dayNum] = todaySold + totoAmount;
    }


    function distribute(uint poolId,TransferInfo[] memory transferInfos) onlyMultiSign external returns(bool) {
        Pool pool = pools[poolId];
        for(uint i=0;i<transferInfos.length;i++) {
            pool.withdraw(address(this),transferInfos[i].spender,transferInfos[i].amount);
        }
        return true;
    }

    function setNextProduction(uint productionAmount) external onlyMultiSign returns(bool) {
        uint before = nextProduction;
        nextProduction = productionAmount;
        emit NextProductionChange(before,nextProduction);
        return true;
    }

    function configurePoolAutoAddress(uint poolId,address autoAirDropAddress) onlyMultiSign external returns(bool) {
        address before = poolAutoAddress[poolId];
        poolAutoAddress[poolId] = autoAirDropAddress;
        emit PoolAutoAddressChange(before,autoAirDropAddress);
        return true;
    }

    function autoAirDrop(uint poolId,TransferInfo[] memory transferInfos) external {
        require(msg.sender == poolAutoAddress[poolId],"Forbidden");
        Pool pool = pools[poolId];
        for(uint i=0;i<transferInfos.length;i++) {
            pool.withdraw(address(this),transferInfos[i].spender,transferInfos[i].amount);
        }
    }


    //划转质押toto矿池
    function transferStakePool(address spender,uint amount) external {
        require(msg.sender==address(ozcoinStake),"Forbidden");
        pools[uint(PoolId.StakePool)].withdraw(address(this),spender,amount);
    }

    function settleStake(uint timestamp) external {
        address _sender = msg.sender;
        require(_sender == contractOwner,"Not my owner");
        ozcoinStake.settle(timestamp);
    }

    function initPool(uint poolId) private {
        Pool newPool = new Pool(poolId);
        pools[poolId] = newPool;
    }

    constructor (uint initialTimestamp,address multiSignWalletAddress,address OZCoinAddress) {
        contractOwner = msg.sender;
        initPool(uint(PoolId.OzGroupPool));
        initPool(uint(PoolId.OzSupporterPool));
        initPool(uint(PoolId.OzFoundationPool));
        initPool(uint(PoolId.StakePool));
        initPool(uint(PoolId.OzbetPool));
        initPool(uint(PoolId.OzbetVipPool));
        setPoolDistributeProportionPrivate(20,15,30,5,20,10);
        multiSignWallet = multiSignWalletAddress;
        address OZCAddress = OZCoinAddress;//address(0xb6571e3DcBf05b34d8718D9be8b57CbF700C15A0);
        address BUSDAddress = address(0xD92E713d051C37EbB2561803a3b5FBAbc4962431);
        ozcoinStake = new OZCoinStake(OZCAddress,multiSignWalletAddress,initialTimestamp);
        supportedContractAddress[OZCAddress] = 1;
        supportedContractAddress[BUSDAddress] = 1;
        uint ten = 10;
        uint baseProduction = 10000000;
        nextProduction = baseProduction.mul(ten.power(decimals));
        initialTime = initialTimestamp;
    }

}