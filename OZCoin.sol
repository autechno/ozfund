// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;


import "library/SafeMath.sol";

interface IERC20 {

    function decimals() external view returns (uint8);
    function allowance(address owner, address spender) external view returns (uint);
    function transfer(address to, uint256 value) external;
    function transferFrom(address from, address to, uint value) external;
}

/*interface SubstitutionToken is IERC20 {
    function transferByLegacy(address from, address to, uint value) external;
    function transferFromByLegacy(address sender, address from, address spender, uint value) external;
    function approveByLegacy(address from, address spender, uint value) external;
    function decreaseApproveByLegacy(address _sender, address _spender, uint _value) external;
}*/


contract OZCoinToken {

    using SafeMath for uint;

    string public constant name = "Ozcoinbeta2";

    string public constant symbol = "OZCbeta2";

    uint8 public constant decimals = 18;

    //初始化时间
    uint public initialTime;

    uint256 private _totalSupply;

    //多签合约地址
    address private multiSignWallet;

    //支持兑换的代币合约
    mapping(address => uint) public supportedContractAddress;

    mapping(address => uint) private balances;

    mapping(address => mapping(address => uint)) public _allowance;

    mapping(address => bool) public isFreeze;

    //permit nance
    mapping(address => uint) public nonces;

    //链上日-生产
    mapping(uint => uint) public dayMint;

    //链上日-销毁
    mapping(uint => uint) public dayBurn;

    //链上日-售出
    mapping(uint => uint) public daySold;

    //链上日-转入
    mapping(uint => mapping(address => uint)) public transferIn;

    //链上日-转出
    mapping(uint => mapping(address => uint)) public transferOut;

    //域分隔符 用于验证permitApprove
    bytes32 private DOMAIN_SEPARATOR;

    //废弃状态
    bool public discarded = false;

    bool public paused = false;

    //替换地址
    address public substitutionAddress;

    address private contractOwner;

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed _owner, address indexed _spender, uint _value);

    event DecreaseApprove(address indexed _owner, address indexed _spender, uint _value);

    event Freeze(address addr);

    event Pause();

    event Unpause();

    event Discard();

    event TransferFailed(address indexed from, address indexed to, uint256 amount, string reason);

    //approve许可
    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

    modifier onlyPayloadSize(uint size){
        require(!(msg.data.length < size+4), "Invalid short address");
        _;
    }

    modifier onlyMultiSign() {
        require(msg.sender == multiSignWallet,'Forbidden');
        _;
    }

    modifier whenNotDiscarded(){
        require(!discarded, "Have been discarded");
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

    function setMultiSignAddress(address newMultiSignAddress) public {
        require(msg.sender == contractOwner, "Not Owner!");
        multiSignWallet = newMultiSignAddress;
    }

    function pause() public onlyMultiSign whenNotPaused {
        paused = true;
        emit Pause();
    }

    function unpause() public onlyMultiSign whenPaused{
        paused = false;
        emit Unpause();
    }


    function hashPermit(Permit memory permit) private view returns (bytes32){
        return keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(
                    keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'),
                    permit.owner,
                    permit.spender,
                    permit.value,
                    permit.nonce,
                    permit.deadline
                ))
            )
        );
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

    function freezeAddress(address addr) onlyMultiSign external returns (bool) {
        isFreeze[addr] = true;
        emit Freeze(addr);
        return true;
    }

    function totalSupply() external view returns (uint){
        return _totalSupply;
    }

    function discard() onlyMultiSign external returns (bool success) {
        discarded = true;
        emit Discard();
        return true;
    }

    function rollbackDiscard() onlyMultiSign external returns (bool success) {
        discarded = false;
        return true;
    }

    function burnFreezeAddressCoin(address freezeAddr,uint _value) onlyMultiSign external returns (bool success) {
        require(isFreeze[freezeAddr],"Not freeze");
        require(balances[freezeAddr] >= _value,"Insufficient funds");
        burn(freezeAddr,_value);
        return true;
    }


    function mint(address spender,uint _value) onlyMultiSign external returns (bool success) {
        return _mint(_value,spender);
    }

    //铸币
    function _mint(uint _value,address spender) private returns (bool success) {
        address _from = 0x0000000000000000000000000000000000000000;
        balances[spender] = balances[spender].add(_value);
        _totalSupply = _totalSupply.add(_value);
        emit Transfer(_from, spender, _value);
        uint dayNum = getDays();
        dayMint[dayNum] = dayMint[dayNum].add(_value);
        return true;
    }

    //销币
    function burn(address owner,uint _value) private returns (bool success) {
        address _to = 0x0000000000000000000000000000000000000000;
        doTransfer(owner, _to, _value);
        return true;
    }

    function balanceOf(address _owner) external view returns (uint balance) {
        return balances[_owner];
    }

    function doTransfer(address _from, address _to, uint _value) private {
        require(!isFreeze[_from] || _to == address(0),"Been frozen");
        uint fromBalance = balances[_from];
        require(fromBalance >= _value, "Insufficient funds");
        balances[_from] = fromBalance.sub(_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(_from, _to, _value);
        if(_to == 0x0000000000000000000000000000000000000000) {
            uint dayNum = getDays();
            _totalSupply = _totalSupply.sub(_value);
            dayBurn[dayNum] = dayBurn[dayNum].add(_value);
        }
    }

    function doApprove(address owner,address _spender,uint _value) private {
        _allowance[owner][_spender] = _value;
        emit Approval(owner,_spender,_value);
    }

    function transfer(address _to, uint _value) external onlyPayloadSize(2 * 32) whenNotDiscarded whenNotPaused returns (bool success) {
        address _owner = msg.sender;
        doTransfer(_owner,_to,_value);
        return true;
    }

    function approve(address _spender, uint _value) external onlyPayloadSize(2 * 32) whenNotDiscarded whenNotPaused returns (bool success){
        address _sender = msg.sender;
        doApprove(_sender,_spender,_value);
        return true;
    }

    function decreaseApprove(address _spender, uint _value) external onlyPayloadSize(2 * 32) whenNotDiscarded whenNotPaused returns (bool success){
        address _sender = msg.sender;
        doDecreaseApprove(_sender, _spender, _value);
        return true;
    }

    function doDecreaseApprove(address _sender, address _spender, uint _value) private {
        uint remaining = _allowance[_sender][_spender];
        remaining = remaining.sub(_value);
        _allowance[_sender][_spender] = remaining;
        emit DecreaseApprove(_sender,_spender,_value);
    }

    function allowance(address _owner, address _spender) external view returns (uint remaining){
        return _allowance[_owner][_spender];
    }

    function transferFrom(address _from, address _to, uint _value) external onlyPayloadSize(3 * 32) whenNotDiscarded whenNotPaused returns (bool success){
        address _sender = msg.sender;
        doTransferFrom(_sender, _from, _to, _value);
        return true;
    }

    function doTransferFrom(address _sender, address _from, address _to, uint _value) private {
        uint remaining = _allowance[_from][_sender];
        require(_value <= remaining,"Insufficient remaining allowance");
        remaining = remaining.sub(_value);
        _allowance[_from][_sender] = remaining;
        doTransfer(_from, _to, _value);
    }

    function permitApprove(Permit memory permit, uint8 v, bytes32 r, bytes32 s) external {
        require(permit.deadline >= block.timestamp, "Expired");
        require(permit.nonce == nonces[permit.owner] ++, "Invalid Nonce");
        bytes32 digest = hashPermit(permit);
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == permit.owner, "Invalid Signature");
        doApprove(permit.owner, permit.spender, permit.value);
    }

    function allowSupportedAddress(address contractAddress) onlyMultiSign external returns(bool) {
        supportedContractAddress[contractAddress] = 1;
        return true;
    }

    function removeSupportedAddressAllow(address contractAddress) onlyMultiSign external returns(bool) {
        supportedContractAddress[contractAddress] = 0;
        return true;
    }

    //使用稳定币兑换OZC
    function exchange(address spender,address contractAddress,uint amount) external {
        require(supportedContractAddress[contractAddress] == 1,"Don't support");
        address _owner = msg.sender;
        address _recipient = address(this);
        IERC20 ierc20Contract = IERC20(contractAddress);
        uint allowanceValue = ierc20Contract.allowance(_owner, _recipient);
        require(allowanceValue >= amount,"Insufficient allowance");
        try ierc20Contract.transferFrom(_owner, _recipient, amount) {
            //转账成功
        } catch Error(string memory reason) {
            // 捕获失败的 revert() 或 require()
            //emit TransferFailed(_owner, _recipient, amount, reason);
            revert(reason);
        } catch (bytes memory /*lowLevelData*/) {
            // 捕获失败的 assert() 或其他低级错误
            //emit TransferFailed(_owner, _recipient, amount, "Low-level error");
            revert("ierc20 transferFrom fail. low level error.");
        }
        uint8 erc20decimals = ierc20Contract.decimals();
        //proportion ozcoin对应erc20比例
        //根据精度差距计算兑换数量默认1:1
        uint ozcAmount = amount;
        uint ten = 10;
        if (erc20decimals < decimals) {
            uint8 decimalsDifference = decimals - erc20decimals;
            uint proportion = ten.power(decimalsDifference);
            ozcAmount = amount.mul(proportion);
        }
        if (erc20decimals > decimals) {
            uint8 decimalsDifference = erc20decimals - decimals;
            uint proportion = ten.power(decimalsDifference);
            ozcAmount = amount.div(proportion);
        }
        uint dayNum = getDays();
        transferIn[dayNum][contractAddress] = transferIn[dayNum][contractAddress].add(amount);
        _mint(ozcAmount,spender);
        daySold[dayNum] = daySold[dayNum] + ozcAmount;
    }

    //使用OZC兑换稳定币
    function reverseExchange(address spender,address contractAddress,uint amount) external {
        require(supportedContractAddress[contractAddress] == 1,"Don't support");
        address owner = msg.sender;
        uint8 erc20decimals = IERC20(contractAddress).decimals();
        //proportion ozcoin对应erc20比例
        //根据精度差距计算兑换数量默认1:1
        uint exAmount = amount;
        uint ten = 10;
        if (erc20decimals<decimals) {
            uint8 decimalsDifference = decimals - erc20decimals;
            uint proportion = ten.power(decimalsDifference);
            exAmount = amount.div(proportion);
        }
        if (erc20decimals>decimals) {
            uint8 decimalsDifference = erc20decimals - decimals;
            uint proportion = ten.power(decimalsDifference);
            exAmount = amount.mul(proportion);
        }
        uint dayNum = getDays();
        transferOut[dayNum][contractAddress] = transferOut[dayNum][contractAddress].add(exAmount);
        burn(owner,amount);
        IERC20(contractAddress).transfer(spender,exAmount);
    }

    function withdrawToken(address contractAddress,address spender,uint amount) onlyMultiSign external {
        require(supportedContractAddress[contractAddress] == 1,"Don't support");
        IERC20(contractAddress).transfer(spender,amount);
    }

    constructor (address multiSignWalletAddress, address usdERC20Address) {
        contractOwner = msg.sender;
        supportedContractAddress[usdERC20Address] = 1;
        multiSignWallet = multiSignWalletAddress;
        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
        initialTime = block.timestamp;
    }

}