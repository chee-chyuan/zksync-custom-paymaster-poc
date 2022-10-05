// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import { IPaymaster, ExecutionResult } from '@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymaster.sol';
import { IPaymasterFlow } from '@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymasterFlow.sol';
import { TransactionHelper, Transaction } from '@matterlabs/zksync-contracts/l2/system-contracts/TransactionHelper.sol';
import '@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol';
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract CustomPaymaster {

    address public constant BOOTLOADER = BOOTLOADER_FORMAL_ADDRESS;
    address public constant ENTRY_POINT = BOOTLOADER;
    mapping(address => bool) public whiteListedErc20s;
    mapping(address => bool) public blackListUsers;
    mapping(address => bool) public admins;

    error NotImplemented();

    constructor(address _admin) {
        admins[_admin] = true;
    }

    function getTokenRateFromEth(address erc20TokenAddr, uint256 ethAmount)
        public
        returns (uint256)
    {
        // could be something that the paymaster sets
        // could be from a reliable oracle
        // or could be based on the exchange rate of a dex

        return ethAmount * 5; // temp value
    }

    function getTokenRateToEth(address erc20TokenAddr, uint256 tokenAmount)
        public
        returns (uint256)
    {
        return tokenAmount / 5; // temp value
    }

    function paymasterFee(uint256 requiredEth) public returns (uint256 fee) {
        return 0;
    }

    function validateAndPayForPaymasterTransaction(
        Transaction calldata _transaction
    ) external payable returns (bytes memory context) {
        require(msg.sender == BOOTLOADER, "Not bootloader");

        require(
            _transaction.paymasterInput.length >= 4,
            "The standard paymaster input must be at least 4 bytes long"
        );

        // check paymaster input. we are checking for approved based selector
        // this method is not actually callable, just a way for us to encode and decode data
        bytes4 paymasterInputSelector = bytes4(
            _transaction.paymasterInput[0:4]
        );

        if (paymasterInputSelector == IPaymasterFlow.approvalBased.selector) {
            // While the actual data consists of address, uint256 and bytes data,
            // the data is some arbitrary input that we may use
            (address token, uint256 amount, ) = abi.decode(
                _transaction.paymasterInput[4:],
                (address, uint256, bytes)
            );

            // saving the current token to context
            // context = bytes(token);
            context = abi.encodePacked(token);

            require(whiteListedErc20s[token], "erc20 not supported");

            address userAddress = address(uint160(_transaction.from));
            require(!blackListUsers[userAddress], "user has been blocklisted");

            // - potentially check if transaction is allowed? (ie. do we want to approve user to perform this transaction)
            //  - eg. lets say we only allow swapping in uniswap, we need to check if the transaction input is allowed
            //  for poc, we allow all transactions

            uint256 requiredETH = _transaction.ergsLimit *
                _transaction.maxFeePerErg;

            // paymaster charge fee for service
            uint256 fee = paymasterFee(requiredETH);
            requiredETH += fee;

            // - swap to eth (dex?)
            uint256 requiredToken = getTokenRateFromEth(token, requiredETH);

            // - check approval
            uint256 userAllowance = IERC20(token).allowance(userAddress, address(this));
            // - check if eth is enough
            require(userAllowance > requiredToken, "not enough approval");

            // - pay all token to paymaster
            IERC20(token).transferFrom(
                userAddress,
                address(this),
                requiredToken
            );

            // - pay bootloader in eth
            // bootloader will check if sufficient eth has been paid before execution
            (bool success, ) = payable(BOOTLOADER).call{value: requiredETH}("");
            require(success, "payment to bootloader fail");
        } else {
            revert NotImplemented();
        }
    }

    function postOp(
        bytes calldata _context,
        Transaction calldata _transaction,
        ExecutionResult _txResult,
        uint256 _maxRefundedErgs // actual gas cost without this postop // _maxRefundedErgs
    ) external payable {
        require(msg.sender == BOOTLOADER, "Not entry point");

        // // implement refund logic
        // // for now we always refund the token back to the user

        // get rate of eth to token
        address erc20TokenAddr = address(uint160(bytes20(_context)));

        uint256 refundedToken = getTokenRateFromEth(
            erc20TokenAddr,
            _maxRefundedErgs * _transaction.maxFeePerErg
        );

        // repay sender the token
        address userAddress = address(uint160(_transaction.from));
        IERC20(erc20TokenAddr).transfer(userAddress, refundedToken);
    }

    // TODO: how to account for gas in the postOp?

    /**
     * allow eth to be transferred to this contract so that the paymaster can provide eth for users
     */
    receive() external payable {}

    modifier onlyAdmin() {
        require(admins[msg.sender], "not admin");
        _;
    }

    function setAdmin(address _admin) external onlyAdmin {
        require(_admin != address(this), "this contract cannot be an admin");
        admins[_admin] = true;
    }

    function setWhitelistToken(address tokenAddr, bool isWhiteList) external onlyAdmin {
        whiteListedErc20s[tokenAddr] = isWhiteList;
    }

    function withdrawToken(
        address token,
        address recipient,
        uint256 amount
    ) external onlyAdmin {
        IERC20(token).transfer(recipient, amount);
    }

    function withdrawEth(address payable recipient, uint256 amount)
        external
        onlyAdmin
    {
        (bool success, ) = recipient.call{value: amount}("");
        require(success);
    }

    

    // Staking
    // add a paymaster stake (must be called by the paymaster)
    // function addStake(uint32 _unstakeDelaySec) external payable

    // // unlock the stake (must wait unstakeDelay before can withdraw)
    // function unlockStake() external

    // // withdraw the unlocked stake
    // function withdrawStake(address payable withdrawAddress) external
}
