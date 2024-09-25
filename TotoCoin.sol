// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./library/SafeMath.sol";
import {Common} from "./library/Common.sol";
import {IERC20} from "./library/IERC20.sol";
import {Ownable} from "./library/Ownable.sol";


interface IUSDT {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external;
    function decimals() external view returns (uint8);
}

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

    function withdraw(address contractAddress, address spender, uint amount) external {
        address _sender = msg.sender;
        require(_sender == contractOwner,"Not my owner");
        IERC20(contractAddress).transfer(spender, amount);
    }

}

contract TotoCoinToken is IERC20, Ownable {

    using SafeMath for uint;

    uint256 private _totalSupply;
    mapping(address => uint) private balances;
    string public constant name = "TOTO";
    string public constant symbol = "TOTO";
    uint8 public constant decimals = 18;

    mapping(address => uint) public supportedExchargeContractAddress;//支持的兑换币
    mapping(address => uint) public authorizedContractAddress;//授权的合约-如质押合约、预售合约

    uint public initialPeriod;
    uint public lastProducePeriod;

    uint public productionLimit;
    uint public nextProduction;
    uint public lastProduction;


    bool public allowExchange = true;

    address private multiSignWallet;

    mapping(uint => Pool) private pools;
    mapping(uint => address) private poolAutoAddress;
    mapping(uint => uint) public poolDistributeProportion;

    uint public constant PRODUCE_PERIOD = 1 days;//生产周期

    mapping(uint => mapping(uint => uint)) public dayPoolProduction;
    //mapping(uint => uint) public dayProduction;

    //mapping(uint => uint) public dayBurn;
    //mapping(uint => uint) public dayMint;

//    mapping(uint => uint) public dayProduction4Stake;
//    mapping(uint => uint) public daySold;
//    mapping(uint => mapping(address => uint)) public transferIn;
//    mapping(uint => mapping(address => uint)) public transferOut;

    mapping (address => mapping (address => uint)) public _allowance;

    bool public paused = false;

//    event ContractOwnerChange(address beforeAddress, address afterAddress);

    event DecreaseApprove(address indexed _owner, address indexed _spender, uint _value);

    event NextProductionChange(uint beforeValue, uint afterValue);

    event PoolAutoAddressChange(address beforeValue, address afterValue);

    event ProductionLimitChange(uint beforeValue, uint afterValue);

    event PoolDistributeProportionChange(uint poolId, uint proportion);

    event Pause();

    event Unpause();


    modifier onlyPayloadSize(uint size){
        require(!(msg.data.length < size+4), "Invalid short address");
        _;
    }

    modifier onlyMultiSign() {
        require(msg.sender == multiSignWallet,"Forbidden");
        _;
    }

    modifier whenNotPaused(){
        require(!paused, "Must be used without pausing");
        _;
    }

    modifier whenPaused(){
        require(paused, "Must be used under pause");
        _;
    }

    function pause() public onlyMultiSign whenNotPaused returns (bool success) {
        paused = true;
        emit Pause();
        return true;
    }

    function unpause() public onlyMultiSign whenPaused returns (bool success) {
        paused = false;
        emit Unpause();
        return true;
    }

    function balanceOf(address _owner) external view returns (uint balance) {
        return balances[_owner];
    }

    function doTransfer(address _from, address _to, uint _value) private {
        uint fromBalance = balances[_from];
        require(fromBalance >= _value, "Insufficient funds");
        balances[_from] = fromBalance.sub(_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(_from, _to, _value);
        if(_to == address(0)) {
            _totalSupply = _totalSupply.sub(_value);
            //uint dayNum = getDays();
            //dayBurn[dayNum] = dayBurn[dayNum].add(_value);
        }
    }

    function doApprove(address owner,address _spender,uint _value) private {
        _allowance[owner][_spender] = _value;
        emit Approval(owner,_spender,_value);
    }

    function transfer(address _to, uint _value) external onlyPayloadSize(2 * 32) whenNotPaused returns (bool success) {
        address _owner = msg.sender;
        doTransfer(_owner,_to,_value);
        return true;
    }

    function approve(address _spender, uint _value) external onlyPayloadSize(2 * 32) whenNotPaused returns (bool success){
        address _sender = msg.sender;
        doApprove(_sender,_spender,_value);
        return true;
    }

    function decreaseApprove(address _spender, uint _value) external onlyPayloadSize(2 * 32) whenNotPaused returns (bool success){
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

    function transferFrom(address _from, address _to, uint _value) external onlyPayloadSize(3 * 32) whenNotPaused returns (bool success){
        address _sender = msg.sender;
        uint remaining = _allowance[_from][_sender];
        require(_value <= remaining,"Insufficient remaining allowance");
        remaining = remaining.sub(_value);
        _allowance[_from][_sender] = remaining;
        doTransfer(_from, _to, _value);
        return true;
    }

    function withdrawToken(address contractAddress,address targetAddress,uint amount) onlyMultiSign external returns(bool) {
        IERC20(contractAddress).transfer(targetAddress,amount);
//        uint dayNum = getDays();
//        transferOut[dayNum][contractAddress] = transferOut[dayNum][contractAddress].add(amount);
        return true;
    }

    function totalSupply() external view returns (uint) {
        return _totalSupply;
    }

    function mint(address spender,uint _value) onlyMultiSign external returns (bool success) {
        return _mint(_value,spender);
    }

    function _mint(uint _value,address spender) private returns (bool success) {
        address _from = address(0);
        balances[spender] = balances[spender].add(_value);
        _totalSupply = _totalSupply.add(_value);
        emit Transfer(_from, spender, _value);
        //uint dayNum = getDays();
        //dayMint[dayNum] = dayMint[dayNum].add(_value);
        return true;
    }

    //销币
    function burn(address owner,uint _value) private returns (bool success) {
        address _to = 0x0000000000000000000000000000000000000000;
        doTransfer(owner, _to, _value);
        return true;
    }

    function setProductionLimit(uint productionLimitV) onlyMultiSign public returns(bool) {
        uint before = productionLimit;
        productionLimit = productionLimitV;
        emit ProductionLimitChange(before,productionLimitV);
        return true;
    }

    function setPoolDistributeProportion(uint ozGroupProportion, uint ozSupportProportion, uint ozFundProportion, uint stakeProportion, uint ozbetProportion, uint ozbetVipProportion) onlyMultiSign public returns(bool) {
        setPoolDistributeProportionPrivate(ozGroupProportion,ozSupportProportion,ozFundProportion,stakeProportion,ozbetProportion,ozbetVipProportion);
        return true;
    }

    function setPoolDistributeProportionPrivate(uint ozGroupProportion, uint ozSupportProportion, uint ozFundProportion, uint stakeProportion, uint ozbetProportion, uint ozbetVipProportion) private {
        require(ozGroupProportion + ozSupportProportion + ozFundProportion + stakeProportion + ozbetProportion + ozbetVipProportion == 100,"Sum must to be 100");
        poolDistributeProportion[uint(Common.PoolId.OzGroupPool)] = ozGroupProportion;
        emit PoolDistributeProportionChange(uint(Common.PoolId.OzGroupPool),ozGroupProportion);
        poolDistributeProportion[uint(Common.PoolId.OzSupporterPool)] = ozSupportProportion;
        emit PoolDistributeProportionChange(uint(Common.PoolId.OzSupporterPool),ozSupportProportion);
        poolDistributeProportion[uint(Common.PoolId.OzFoundationPool)] = ozFundProportion;
        emit PoolDistributeProportionChange(uint(Common.PoolId.OzFoundationPool),ozFundProportion);
        poolDistributeProportion[uint(Common.PoolId.StakePool)] = stakeProportion;
        emit PoolDistributeProportionChange(uint(Common.PoolId.StakePool),stakeProportion);
        poolDistributeProportion[uint(Common.PoolId.OzbetPool)] = ozbetProportion;
        emit PoolDistributeProportionChange(uint(Common.PoolId.OzbetPool),ozbetProportion);
        poolDistributeProportion[uint(Common.PoolId.OzbetVipPool)] = ozbetVipProportion;
        emit PoolDistributeProportionChange(uint(Common.PoolId.OzbetVipPool),ozbetVipProportion);
    }

    function setContractOwner(address newOwner) onlyMultiSign external returns (bool) {
        _transferOwnership(newOwner);
        return true;
    }

    function addAuthorizedContractAddress(address contractAddress) onlyMultiSign external returns (bool) {
        authorizedContractAddress[contractAddress] = 1;
        return true;
    }
    function subAuthorizedContractAddress(address contractAddress) onlyMultiSign external returns (bool) {
        delete authorizedContractAddress[contractAddress];
        return true;
    }

    function addExchargeContractAddress(address contractAddress) onlyMultiSign external returns (bool) {
        supportedExchargeContractAddress[contractAddress] = 1;
        return true;
    }
    function subExchargeContractAddress(address contractAddress) onlyMultiSign external returns (bool) {
        delete supportedExchargeContractAddress[contractAddress];
        return true;
    }

    function produce2Pool(uint period, uint poolId, uint amount) private {
        address poolAddress = address(pools[poolId]);
        doTransfer(address(this), poolAddress, amount);
        dayPoolProduction[period][poolId] = amount;
    }

    function produce(uint timestamp) external onlyOwner returns (bool) {
        require( timestamp < block.timestamp,"Exception call : can not after the block");
        uint period = getPeriod(timestamp);
        require( period > 0, "Exception call time, In the cooling.");//临时屏蔽 测试用
        require( period > lastProducePeriod, "Exception call time, In the cooling.");
        require(( _totalSupply + nextProduction <= productionLimit) || productionLimit == 0 ,"Production Limit");
        _mint(nextProduction,address(this));
        //dayProduction[period] = nextProduction;
        lastProduction = nextProduction;
        uint ozGroupPoolAmount = nextProduction.mul(poolDistributeProportion[uint(Common.PoolId.OzGroupPool)]).div(100);
        produce2Pool(period,uint(Common.PoolId.OzGroupPool),ozGroupPoolAmount);

        uint ozSupporterPoolAmount = nextProduction.mul(poolDistributeProportion[uint(Common.PoolId.OzSupporterPool)]).div(100);
        produce2Pool(period,uint(Common.PoolId.OzSupporterPool),ozSupporterPoolAmount);

        uint ozFoundationPoolAmount = nextProduction.mul(poolDistributeProportion[uint(Common.PoolId.OzFoundationPool)]).div(100);
        produce2Pool(period,uint(Common.PoolId.OzFoundationPool),ozFoundationPoolAmount);

        uint stakePoolAmount = nextProduction.mul(poolDistributeProportion[uint(Common.PoolId.StakePool)]).div(100);
        produce2Pool(period,uint(Common.PoolId.StakePool),stakePoolAmount);

        uint ozbetPoolAmount = nextProduction.mul(poolDistributeProportion[uint(Common.PoolId.OzbetPool)]).div(100);
        produce2Pool(period,uint(Common.PoolId.OzbetPool),ozbetPoolAmount);

        uint ozbetVipPoolAmont = nextProduction.mul(poolDistributeProportion[uint(Common.PoolId.OzbetVipPool)]).div(100);
        produce2Pool(period,uint(Common.PoolId.OzbetVipPool),ozbetVipPoolAmont);

        uint minProduction = uint(1000000).mul(uint(10).power(decimals));//10万
        if(nextProduction > minProduction) {
            nextProduction = nextProduction.mul(9999).div(10000);
            emit NextProductionChange(lastProduction,nextProduction);
        } else {
            nextProduction = minProduction;
        }
        lastProducePeriod = period;
        return true;
    }

    function getPoolProductinByPeriod(uint period, Common.PoolId poolId) public view returns (uint) {
        return dayPoolProduction[period][uint(poolId)];
    }

    function getPeriod(uint timestamp) public view returns (uint) {
        uint _timePeriod = timestamp / PRODUCE_PERIOD;
        if(_timePeriod < initialPeriod) {
            return 0;
        }
        return _timePeriod - initialPeriod + 1;
    }

    function getDays() public view returns (uint) {
        return getPeriod(block.timestamp);
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
        require(supportedExchargeContractAddress[contractAddress] == 1,"Don't support");
        require(allowExchange,"Not allow");
        address owner = msg.sender;
        uint allowanceValue = IERC20(contractAddress).allowance(owner,address(this));
        require(allowanceValue >= amount,"Insufficient allowance");
        bool res = IERC20(contractAddress).transferFrom(owner,address(this),amount);
        require(res,"Transfer failed");
        uint8 erc20decimals = IERC20(contractAddress).decimals();
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
        _mint(totoAmount,spender);
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

    //清空矿池-质押合约
    function burnPool(Common.PoolId poolId) external returns (bool success) {
        require(authorizedContractAddress[msg.sender] == 1, "Forbidden");
        address poolAddress = address(pools[uint(poolId)]);
        uint amount = balances[poolAddress];
        return burn(poolAddress, amount);
    }
    //划转质押toto矿池-质押合约
    function transferStakePool(Common.PoolId poolId, address spender, uint amount) external {
        require(authorizedContractAddress[msg.sender]==1,"Forbidden");
        pools[uint(poolId)].withdraw(address(this), spender, amount);
    }
    //预售-预售合约
    function presale(address spender, uint amount) external {
        require(authorizedContractAddress[msg.sender]==1,"Forbidden");
        _mint(amount, spender);
    }

    function initPool(uint poolId) private {
        Pool newPool = new Pool(poolId);
        pools[poolId] = newPool;
    }

    constructor (uint initialTimestamp,address multiSignWalletAddress,address ozCoinAddress) Ownable(msg.sender) {
        initPool(uint(Common.PoolId.OzGroupPool));
        initPool(uint(Common.PoolId.OzSupporterPool));
        initPool(uint(Common.PoolId.OzFoundationPool));
        initPool(uint(Common.PoolId.StakePool));
        initPool(uint(Common.PoolId.OzbetPool));
        initPool(uint(Common.PoolId.OzbetVipPool));
        setPoolDistributeProportionPrivate(20,15,30,5,20,10);
        multiSignWallet = multiSignWalletAddress;
        supportedExchargeContractAddress[ozCoinAddress] = 1;

        uint ten = 10;
        uint baseProduction = 10000000;//初始1000万
        nextProduction = baseProduction.mul(ten.power(decimals));
        if (initialTimestamp == 0) {
            initialPeriod = block.timestamp / PRODUCE_PERIOD;
        } else {
            initialPeriod = initialTimestamp / PRODUCE_PERIOD;
        }
    }

}