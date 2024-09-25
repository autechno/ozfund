// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./library/SafeMath.sol";
import {IERC20} from "./library/IERC20.sol";
import {Common} from "./library/Common.sol";

interface IOzCoin is IERC20 {
    function permitApprove(Common.Permit memory permit, uint8 v, bytes32 r, bytes32 s) external;
}
interface IToto is IERC20 {
    function presale(address spender, uint amount) external;
}

contract TotoPresaleContract {

    using SafeMath for uint;

    address private multiSignWallet;
    address private ozCoinContractAddress;
    address private totoCoinContractAddress;

    bool public paused = false;

    uint public presaleBeginTime;
    uint public presaleEndTime;
    uint public presaleTotalAmount=0;//0表示不限量
    uint public presaleAmountDaily=0;//0表示不限量
    uint public saleAmount;//总销售余额
    mapping(uint => uint) public saleAmountDaily;//每日余额

    event SetPresaleLimit(uint presaleBeginTime,uint presaleEndTime,uint presaleTotalAmount,uint presaleAmountDaily);

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

    function pause() public onlyMultiSign whenNotPaused {
        paused = true;
        emit Pause();
    }

    function unpause() public onlyMultiSign whenPaused {
        paused = false;
        emit Unpause();
    }

    function setPresaleLimit(uint beginTime,uint endTime,uint totalAmount,uint amountDaily) /*onlyMultiSign*/ external {
        presaleBeginTime = beginTime;
        presaleEndTime = endTime;
        presaleTotalAmount=totalAmount;//0表示不限量
        presaleAmountDaily=amountDaily;//0表示不限量
        emit SetPresaleLimit( beginTime, endTime, totalAmount, amountDaily);
    }

    //提取合约地址内的通证
    function withdrawToken(address contractAddress,address targetAddress,uint amount) onlyMultiSign external returns(bool) {
        IERC20(contractAddress).transfer(targetAddress,amount);
        return true;
    }


    function checkPresaleTime(uint timestamp) private view returns(bool) {
        if(timestamp >= presaleBeginTime && timestamp <= presaleEndTime) {
            return true;
        }
        return false;
    }
    function checkAmountTotally(uint amount) private view returns(bool) {
        if(presaleTotalAmount > 0) {
            if(saleAmount + amount > presaleTotalAmount) {
                return false;
            }
        }
        return true;
    }
    function checkAmountDaily(uint amount) private view returns(bool) {
        if(presaleAmountDaily > 0) {
            if(saleAmountDaily[block.timestamp / 1 days] + amount > presaleAmountDaily){
                return false;
            }
        }
        return true;
    }

    //使用稳定币兑换TOTO
    function sale(uint amount,uint nonce,uint deadline,uint8 v, bytes32 r, bytes32 s) whenNotPaused external {
        require(checkPresaleTime(block.timestamp),"Not within the valid time");
        //proportion toto对应erc20比例
        uint totoAmount = amount;
        require(checkAmountTotally(totoAmount),"total amount overflow");
        require(checkAmountDaily(totoAmount),"daily amount overflow");

        address from = msg.sender;
        address to = address(this);
        Common.Permit memory permit = Common.Permit(from,to,amount,nonce,deadline);
        IOzCoin(ozCoinContractAddress).permitApprove(permit,v,r,s);
        IOzCoin(ozCoinContractAddress).transferFrom(from,to,amount);

        IToto(totoCoinContractAddress).presale(from, totoAmount);
        saleAmount += totoAmount;
        saleAmountDaily[block.timestamp / 1 days] += totoAmount;
    }

    constructor (address multiSignWalletAddress,address ozCoinAddress,address totoCoinAddress) {
        multiSignWallet = multiSignWalletAddress;
        ozCoinContractAddress = ozCoinAddress;
        totoCoinContractAddress = totoCoinAddress;
    }

}