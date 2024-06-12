pragma solidity ^0.8.7;


import "library/SafeMath.sol";

contract MultiSignWallet {

    //提交事务
    event SubmitTransaction(uint transactionId);
    //确认事务(签名)
    event ConfirmTransaction(address admin,uint transactionId);
    //执行事务
    event ExecuteTransaction(uint transactionId);

    using SafeMath for uint;

    //事务类型
    enum TransactionMethod { Pass, SwitchExchange, SetProductionLimit, SetNextProduction, SetPoolDistributeProportion, AllowSupportedAddress, RemoveSupportedAddressAllow, ConfigurePoolAutoAddress, WithdrawToken, Distribute, SetContractOwner, FreezeAddress, BurnFreezeAddressCoin, Mint, AddAdmin, RemoveAdmin, AddSuperAdmin, RemoveSuperAdmin, ChangeAccountStakeExpirationTimestamp, Pause, Unpause, Discard, RollbackDiscard }

    //事务状态
    enum Status { Pending, Executed }

    //管理员类型
    enum AdminType { None, Super, Commmon}

    //事务id-递增
    uint transactionId = 0;

    //事务结构体
    struct Transaction {
        address targetAddress;
        bytes data;
        uint8 transactionType;
        uint8 status;
    }

    //超级管理员地址
    address[] superAdmins = new address[](1);

    //管理员地址
    address[] admins = new address[](1);

    //超级管理员索引映射
    mapping(address => uint) public superAdminIndex;

    //管理员索引映射
    mapping(address => uint) public adminIndex;

    //管理员类型映射
    mapping(address => uint8) public adminType;

    //bytes4事务类型映射
    mapping(bytes4 => uint8) transactionFunctionType;

    //事务-管理员签名映射
    mapping(uint => mapping(address => uint)) public transactionConfirm;

    //事务-超级管理员签名数
    mapping(uint => uint) public transactionSuperAdminConfirmCount;

    //事务-管理员签名数
    mapping(uint => uint) public transactionAdminConfirmCount;

    //事务方法需管理员签名映射
    mapping(uint => uint) transactionMethodNeedAdminConfirm;

    //事务方法需超级管理员签名映射
    mapping(uint => uint) transactionMethodNeedSuperAdminConfirm;

    //事务id-结构体映射
    mapping(uint => Transaction) transactionMap;

    //仅允许直接访问修饰
    modifier onlySelf() {
        require(msg.sender == address(this),'Forbidden');
        _;
    }

    //提交事务方法
    function submitTransaction(address targetAddress,bytes memory data) external returns (uint){
        bytes4 method = inputDataDecode(data);
        uint8 thisTransactionType = transactionFunctionType[method];
        require(thisTransactionType > 0,'Exception call');
        Transaction memory transaction = Transaction(targetAddress,data,thisTransactionType,uint8(Status.Pending));
        uint thisTransactionId = transactionId;
        transactionId = transactionId.add(1);
        transactionMap[thisTransactionId] = transaction;
        confirmTransaction(thisTransactionId);
        emit SubmitTransaction(thisTransactionId);
        return thisTransactionId;
    }

    //输入解码方法
    function inputDataDecode(bytes memory data) pure public returns (bytes4) {
        bytes memory data2 = new bytes(data.length);
        bytes4 method = data[0] | bytes4(data[1]) >> 8 | bytes4(data[2]) >> 16 | bytes4(data[3]) >> 24;
        for (uint256 i=0; i < data.length - 4; ) {
            data2[i] = data[i + 4];
            unchecked {++i;}
        }
        //string memory str) = abi.decode(data2,(string));
        return method;
    }

    //查看事务结构
    function viewTransaction(uint viewTransactionId) view public returns (Transaction memory) {
        return transactionMap[viewTransactionId];
    }

    //确认事务
    function confirmTransaction(uint confirmTransactionId) public {
        require(transactionConfirm[confirmTransactionId][msg.sender] == 0,'Repeat confirm');
        transactionConfirm[confirmTransactionId][msg.sender] = 1;
        require(adminType[msg.sender] > 0,'Exception call');
        if(adminType[msg.sender] == uint8(AdminType.Super)) {
            transactionSuperAdminConfirmCount[confirmTransactionId] = transactionSuperAdminConfirmCount[confirmTransactionId].add(1);
        }
        if(adminType[msg.sender] == uint8(AdminType.Commmon)) {
            transactionAdminConfirmCount[confirmTransactionId] = transactionAdminConfirmCount[confirmTransactionId].add(1);
        }
        uint8 executeTransactionType = transactionMap[confirmTransactionId].transactionType;
        if(transactionAdminConfirmCount[confirmTransactionId]>=transactionMethodNeedAdminConfirm[executeTransactionType] && transactionSuperAdminConfirmCount[confirmTransactionId]>=transactionMethodNeedSuperAdminConfirm[executeTransactionType]) {
            executeTransaction(confirmTransactionId);
        }
        emit ConfirmTransaction(msg.sender, confirmTransactionId);
    }

    //执行事务
    function executeTransaction(uint executeTransactionId) private {
        require(transactionMap[executeTransactionId].status==uint8(Status.Pending),'Repeat execute');
        transactionMap[executeTransactionId].status=uint8(Status.Executed);
        (bool success, ) = transactionMap[executeTransactionId].targetAddress.call{value: 0 ether}(transactionMap[executeTransactionId].data);
        require(success,'Execution failed');
        emit ExecuteTransaction(executeTransactionId);
    }

    //添加管理员
    function addAdmin(address admin) onlySelf public returns (bool) {
        doAddAdmin(admin);
        return true;
    }

    //执行添加管理员
    function doAddAdmin(address admin) private returns (bool) {
        require(admins.length <= 4,'Number of Admin Limit');
        admins.push(admin);
        adminIndex[admin] = admins.length - 1;
        adminType[admin] = uint8(AdminType.Commmon);
        return true;
    }

    //移除管理员
    function removeAdmin(address admin) onlySelf public returns (bool) {
        uint index = adminIndex[admin];
        require(index>0,"Nonexistent");
        require((admins.length + superAdmins.length) > 4,"Number of Admin Limit");
        admins[index] = admins[admins.length - 1];
        admins.pop();
        delete adminType[admin];
        return true;
    }

    //添加超级管理员
    function addSuperAdmin(address superAdmin) onlySelf public returns (bool) {
        return doAddSuperAdmin(superAdmin);
    }

    //执行添加超级管理员
    function doAddSuperAdmin(address superAdmin) private returns (bool) {
        require(superAdmins.length <= 3,'Number of SuperAdmin Limit');
        superAdmins.push(superAdmin);
        superAdminIndex[superAdmin] = superAdmins.length - 1;
        adminType[superAdmin] = uint8(AdminType.Super);
        return true;
    }

    //移除超级管理员
    function removeSuperAdmin(address superAdmin) onlySelf public returns (bool) {
        uint index = superAdminIndex[superAdmin];
        require(index > 0,"Nonexistent");
        require((admins.length + superAdmins.length) > 4,"Number of Admin Limit");
        superAdmins[index] = superAdmins[superAdmins.length - 1];
        superAdmins.pop();
        delete adminType[superAdmin];
        return true;
    }

    //配置某类型事务配置
    function configTransactionType(uint8 transactionMethodId, bytes4 method, uint8 adminConfirm, uint superAdminConfirm) private {
        transactionFunctionType[method] = transactionMethodId;
        transactionMethodNeedAdminConfirm[transactionMethodId] = adminConfirm;
        transactionMethodNeedSuperAdminConfirm[transactionMethodId] = superAdminConfirm;
    }

    //构造 初始化各类事务配置  初始化管理员
    constructor () {

        unchecked {

        configTransactionType(uint8(TransactionMethod.SwitchExchange),0x92918f09,2,2);
        configTransactionType(uint8(TransactionMethod.SetProductionLimit),0x4bb6640d,3,2);
        configTransactionType(uint8(TransactionMethod.SetNextProduction),0x56cf12a0,2,2);
        configTransactionType(uint8(TransactionMethod.SetPoolDistributeProportion),0xefbd8400,3,2);
        configTransactionType(uint8(TransactionMethod.AllowSupportedAddress),0xe5d9b06e,2,2);
        configTransactionType(uint8(TransactionMethod.RemoveSupportedAddressAllow),0xadb29444,2,2);
        configTransactionType(uint8(TransactionMethod.ConfigurePoolAutoAddress),0x32e38ed5,2,2);
        configTransactionType(uint8(TransactionMethod.WithdrawToken),0x01e33667,2,2);
        configTransactionType(uint8(TransactionMethod.Distribute),0xa3a9c4fe,2,2);
        configTransactionType(uint8(TransactionMethod.SetContractOwner),0xa34d42b8,2,2);
        configTransactionType(uint8(TransactionMethod.FreezeAddress),0x51e946d5,2,1);
        configTransactionType(uint8(TransactionMethod.BurnFreezeAddressCoin),0x1ee08b69,2,2);
        configTransactionType(uint8(TransactionMethod.Mint),0x40c10f19,2,2);
        configTransactionType(uint8(TransactionMethod.ChangeAccountStakeExpirationTimestamp),0xcb8de7cc,2,2);
        configTransactionType(uint8(TransactionMethod.Pause),0x8456cb59,2,2);
        configTransactionType(uint8(TransactionMethod.Unpause),0x3f4ba83a,2,2);
        configTransactionType(uint8(TransactionMethod.Discard),0xd4881113,3,2);
        configTransactionType(uint8(TransactionMethod.RollbackDiscard),0x6e593a3b,3,2);


        configTransactionType(uint8(TransactionMethod.AddAdmin),0x70480275,0,2);
        configTransactionType(uint8(TransactionMethod.RemoveAdmin),0x1785f53c,0,2);
        configTransactionType(uint8(TransactionMethod.AddSuperAdmin),0xb3292ff0,2,1);
        configTransactionType(uint8(TransactionMethod.RemoveSuperAdmin),0x4902e4aa,2,1);


        superAdmins.push();
        doAddSuperAdmin(0x54e5F9f440eD87546a8F34701a5d26919796e375);
        doAddSuperAdmin(0x21923e1bc2529de136526fFb1e848531A6585EF4);
        //doAddSuperAdmin(0x946E1e444B4de317E588750f0a0b3913fa8BCAaA);
        //doAddSuperAdmin(0xa2B3510CA4aDe864Fc972a31ec4103D3E158a8c4);

        admins.push();
        doAddAdmin(0x966F3dE8091d185F56B5706c2502c19d919CA21e);
        doAddAdmin(0x64859F722426b250b75C3058A81891cF9F9840f1);
        doAddAdmin(0xD6b0d9BB62605d71215643707B34482d03018f95);
        //doAddAdmin(0x696B1E4e3ae3f8278936ea1bc58BcB4BE38A52a9);
        //doAddAdmin(0xf8FB56125dD3509A53b991fB72DD60Be0A227BDF);
        //doAddAdmin(0x52d13CBbfe2bc7fEF61e830d7ff9dfbe3EC7dDDd);

        }

    }

}