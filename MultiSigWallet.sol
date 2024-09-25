// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;


import "./library/SafeMath.sol";

contract MultiSignWallet {

    //提交事务
    event SubmitTransaction(uint transactionId);
    //确认事务(签名)
    event ConfirmTransaction(address admin,uint transactionId);
    //执行事务
    event ExecuteTransaction(uint transactionId);

    using SafeMath for uint;

    //事务状态
    enum Status { Pending, Executed }

    //管理员类型
    enum AdminType { None, Super, Commmon}

    //事务id-递增
    uint private transactionId = 0;

    //事务结构体
    struct Transaction {
        address targetAddress;
        bytes data;
        bytes4 transactionType;
        uint8 status;
    }

    //超级管理员地址
    address[] public superAdmins = new address[](1);
    //管理员地址
    address[] public admins = new address[](1);
    //管理员类型映射
    mapping(address => uint8) public adminType;

    //事务-管理员签名映射
    mapping(uint => mapping(address => uint)) public transactionConfirm;
    //事务-超级管理员签名数
    mapping(uint => uint) public transactionSuperAdminConfirmCount;
    //事务-管理员签名数
    mapping(uint => uint) public transactionAdminConfirmCount;

    //事务方法需管理员签名映射
    mapping(bytes4 => uint8) private transactionMethodNeedAdminConfirm;
    //事务方法需超级管理员签名映射
    mapping(bytes4 => uint8) private transactionMethodNeedSuperAdminConfirm;

    //事务id-结构体映射
    mapping(uint => Transaction) private transactionMap;

    //仅允许直接访问修饰
    modifier onlySelf() {
        require(msg.sender == address(this),'Forbidden');
        _;
    }

    //输入解码方法
    function inputDataDecode(bytes memory data) pure public returns (bytes4) {
        bytes4 method = data[0] | bytes4(data[1]) >> 8 | bytes4(data[2]) >> 16 | bytes4(data[3]) >> 24;
        bytes memory data2 = new bytes(data.length);
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

    //提交事务方法
    function submitTransaction(address targetAddress,bytes memory data) external returns (uint){
        bytes4 method = inputDataDecode(data);
        require(transactionMethodNeedAdminConfirm[method] + transactionMethodNeedSuperAdminConfirm[method] > 0,'Exception call');//需要签名的方法

        Transaction memory transaction = Transaction(targetAddress,data,method,uint8(Status.Pending));
        uint thisTransactionId = transactionId;
        transactionId = transactionId.add(1);
        transactionMap[thisTransactionId] = transaction;
        confirmTransaction(thisTransactionId);
        emit SubmitTransaction(thisTransactionId);
        return thisTransactionId;
    }

    //确认事务
    function confirmTransaction(uint confirmTransactionId) public {
        require(adminType[msg.sender] > 0,'Exception call');
        require(transactionConfirm[confirmTransactionId][msg.sender] == 0,'Repeat confirm');
        bytes4 executeTransactionType = transactionMap[confirmTransactionId].transactionType;
        uint superAdminConfirmCount = transactionSuperAdminConfirmCount[confirmTransactionId];
        uint adminConfirmCount = transactionAdminConfirmCount[confirmTransactionId];
        if(adminType[msg.sender] == uint8(AdminType.Super)) {
            require(superAdminConfirmCount < transactionMethodNeedSuperAdminConfirm[executeTransactionType],'Sign Number of SuperAdmin Limited.');
            superAdminConfirmCount = superAdminConfirmCount.add(1);
        }
        if(adminType[msg.sender] == uint8(AdminType.Commmon)) {
            require(adminConfirmCount < transactionMethodNeedAdminConfirm[executeTransactionType],'Sign Number of Admin Limited.');
            adminConfirmCount = adminConfirmCount.add(1);
        }
        if(adminConfirmCount >= transactionMethodNeedAdminConfirm[executeTransactionType] && superAdminConfirmCount >= transactionMethodNeedSuperAdminConfirm[executeTransactionType]) {
            executeTransaction(confirmTransactionId);
        }

        transactionConfirm[confirmTransactionId][msg.sender] = 1;
        if(adminType[msg.sender] == uint8(AdminType.Super)) {
            transactionSuperAdminConfirmCount[confirmTransactionId] = superAdminConfirmCount;
        }
        if(adminType[msg.sender] == uint8(AdminType.Commmon)) {
            transactionAdminConfirmCount[confirmTransactionId] = adminConfirmCount;
        }
        emit ConfirmTransaction(msg.sender, confirmTransactionId);
    }

    //执行事务
    function executeTransaction(uint executeTransactionId) private {
        require(transactionMap[executeTransactionId].status==uint8(Status.Pending),'Repeat execute');
        (bool success, ) = transactionMap[executeTransactionId].targetAddress.call{value: 0 ether}(transactionMap[executeTransactionId].data);
        //(bool success, bytes memory data) =
        // 解析返回的数据
        //(uint returnValue) = abi.decode(data, (uint));
        require(success,'Execution failed');
        transactionMap[executeTransactionId].status=uint8(Status.Executed);
        emit ExecuteTransaction(executeTransactionId);
    }

    //查看超管s
    function viewSuperAdmins() view public returns (address[] memory) {
        return superAdmins;
    }
    //查看普管s
    function viewAdmins() view public returns (address[] memory) {
        return admins;
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
        adminType[admin] = uint8(AdminType.Commmon);
        return true;
    }

    //移除管理员
    function removeAdmin(address admin) onlySelf public returns (bool) {
        require((admins.length + superAdmins.length) > 4,"Number of Admin Limit");
        uint length = admins.length;
        for (uint i = 0; i < length; i++) {
            if (admins[i] == admin) {
                // 替换要删除的元素与数组的最后一个元素
                admins[i] = admins[length - 1];
                // 删除数组的最后一个元素
                admins.pop();
                break; // 删除第一个匹配值后退出循环
            }
        }
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
        adminType[superAdmin] = uint8(AdminType.Super);
        return true;
    }

    //移除超级管理员
    function removeSuperAdmin(address superAdmin) onlySelf public returns (bool) {
        require((admins.length + superAdmins.length) > 4,"Number of SuperAdmin Limit");
        uint length = superAdmins.length;
        for (uint i = 0; i < length; i++) {
            if (superAdmins[i] == superAdmin) {
                // 替换要删除的元素与数组的最后一个元素
                superAdmins[i] = superAdmins[length - 1];
                // 删除数组的最后一个元素
                superAdmins.pop();
                break; // 删除第一个匹配值后退出循环
            }
        }
        delete adminType[superAdmin];
        return true;
    }

    //配置某类型事务配置
    function configTransactionType(bytes4 method, uint8 adminConfirm, uint8 superAdminConfirm) onlySelf public returns (bool) {
        transactionMethodNeedAdminConfirm[method] = adminConfirm;
        transactionMethodNeedSuperAdminConfirm[method] = superAdminConfirm;
        return true;
    }

    //配置某类型事务配置
    function _configTransactionType(bytes4 method, uint8 adminConfirm, uint8 superAdminConfirm) private {
        transactionMethodNeedAdminConfirm[method] = adminConfirm;
        transactionMethodNeedSuperAdminConfirm[method] = superAdminConfirm;
    }

    //构造 初始化各类事务配置  初始化管理员
    constructor () {

        unchecked {
            _configTransactionType(0xb07224c7,2,2);//configTransactionType
            _configTransactionType(0x92918f09,2,2);//uint8(TransactionMethod.SwitchExchange),
            _configTransactionType(0x4bb6640d,3,2);//uint8(TransactionMethod.SetProductionLimit),
            _configTransactionType(0x56cf12a0,2,2);//uint8(TransactionMethod.SetNextProduction),
            _configTransactionType(0xefbd8400,3,2);//uint8(TransactionMethod.SetPoolDistributeProportion),
            _configTransactionType(0xe5d9b06e,2,2);//uint8(TransactionMethod.AllowSupportedAddress),
            _configTransactionType(0xadb29444,2,2);//uint8(TransactionMethod.RemoveSupportedAddressAllow),
            _configTransactionType(0x32e38ed5,2,2);//uint8(TransactionMethod.ConfigurePoolAutoAddress),
            _configTransactionType(0x01e33667,2,2);//uint8(TransactionMethod.WithdrawToken),
            _configTransactionType(0xa3a9c4fe,2,2);//uint8(TransactionMethod.Distribute),
            _configTransactionType(0xa34d42b8,2,2);//uint8(TransactionMethod.SetContractOwner),
            _configTransactionType(0x51e946d5,2,1);//uint8(TransactionMethod.FreezeAddress),
            _configTransactionType(0x1ee08b69,2,2);//uint8(TransactionMethod.BurnFreezeAddressCoin),
            _configTransactionType(0x40c10f19,2,2);//uint8(TransactionMethod.Mint),
            _configTransactionType(0xcb8de7cc,2,2);//uint8(TransactionMethod.ChangeAccountStakeExpirationTimestamp),
            _configTransactionType(0x8456cb59,2,2);//uint8(TransactionMethod.Pause),
            _configTransactionType(0x3f4ba83a,2,2);//uint8(TransactionMethod.Unpause),
            _configTransactionType(0xd4881113,3,2);//uint8(TransactionMethod.Discard),
            _configTransactionType(0x6e593a3b,3,2);//uint8(TransactionMethod.RollbackDiscard),

            _configTransactionType(0x70480275,2,1);//uint8(TransactionMethod.AddAdmin),
            _configTransactionType(0x1785f53c,2,1);//uint8(TransactionMethod.RemoveAdmin),
            _configTransactionType(0xb3292ff0,3,1);//uint8(TransactionMethod.AddSuperAdmin),
            _configTransactionType(0x4902e4aa,3,1);//uint8(TransactionMethod.RemoveSuperAdmin),

            _configTransactionType(0x87b22030,2,2);//uint8(TransactionMethod.SetAuthorizedContractAddress),
            _configTransactionType(0x162574ea,2,2);//uint8(TransactionMethod.SetAuthorizedContractAddress),
            _configTransactionType(0xee93d9c4,2,2);//uint8(TransactionMethod.SetPresaleLimit),

            doAddSuperAdmin(0xE9eE90f76119B01F45FE5343Da588bd33a510302);
            doAddSuperAdmin(0xB05bD7ab36421Ce07D91d0b85dfa3c83c3C15573);
            doAddAdmin(0x8C5A3B3822D3383CC7fcB61226357A87A6B124FC);
            doAddAdmin(0xfd6201054A5E8D02f3602C8dbEa626A3A88C4A5a);
            doAddAdmin(0xf97bBF2179fcb382cc08CBF6cE6E8ce683A1E67f);
        }

    }

}