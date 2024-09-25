// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library Common {

    enum PoolId {
        Pass,
        OzGroupPool,
        OzSupporterPool,
        OzFoundationPool,
        StakePool,
        OzbetPool,
        OzbetVipPool
    }

    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

}
