pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "./Pausable.sol";

// another one is ByzantineSimpleSwapBridge.
contract ByzantineSimpleSwapBridge is Ownable, Pausable {
    using SafeMath for uint256;

    mapping (address => bool) public supportedTokens;

    uint256 public swapCount;

    address public feeWallet;

    uint256 public feeRatio;    // default to 100, denominator is 10000

    /// Event created on initilizing token dex in source network.
    event TokenSwapped(
    uint256 indexed swapId, address from, bytes32 to, uint256 amount, address token, uint256 fee, uint256 srcNetwork, uint256 dstNetwork);

    event ClaimedTokens(address indexed _token, address indexed _controller, uint _amount);


    /// Constructor.
    constructor (
        address _feeWallet,
        uint256 _feeRatio
    ) public
    {
        feeWallet = _feeWallet;
        feeRatio = _feeRatio;
    }

    //users initial the exchange token with token method of "approveAndCall" in the source chain network
    //then invoke the following function in this contract
    //_amount include the fee token
    function receiveApproval(address from, uint256 _amount, address _token, bytes _data) public whenNotPaused {

        require(supportedTokens[_token], "Not suppoted token.");
        require(msg.sender == _token, "Invalid msg sender for this tx.");

        uint256 swapAmount;
        uint256 dstNetwork;
        bytes32 receiver;

        // swapAmount - token amount
        // dstNetwork -  1:Atlantis 2: Byzantine
        // receiver - receiver address of target network
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize)
            swapAmount := mload(add(ptr, 164))
            dstNetwork := mload(add(ptr, 196))
            receiver :=  mload(add(ptr, 228))
        }

        require(swapAmount > 0, "Swap amount must be larger than zero.");

        uint256 requiredFee = querySwapFee(swapAmount);
        require(_amount >= swapAmount.add(requiredFee), "No enough of token amount are approved.");

        if(requiredFee > 0) {
            require(ERC20(_token).transferFrom(from, feeWallet, requiredFee), "Fee transfer failed.");
        }

        require(ERC20(_token).transferFrom(from, this, swapAmount), "Swap amount transfer failed.");

        emit TokenSwapped(swapCount, from, receiver, swapAmount, _token, requiredFee, 200000, dstNetwork);
        
        swapCount = swapCount + 1;
    }

    function addSupportedToken(address _token) public onlyOwner {
        supportedTokens[_token] = true;
    }

    function removeSupportedToken(address _token) public onlyOwner {
        supportedTokens[_token] = false;
    }

    function changeFeeWallet(address _newFeeWallet) public onlyOwner {
        feeWallet = _newFeeWallet;
    }

    function changeFeeRatio(uint256 _feeRatio) public onlyOwner {
        feeRatio = _feeRatio;
    }

    function querySwapFee(uint256 _amount) public view returns (uint256) {
        uint256 requiredFee = feeRatio.mul(_amount).div(10000);
        return requiredFee;
    }

    function claimTokens(address _token) public onlyOwner {
        if (_token == 0x0) {
            address(msg.sender).transfer(address(this).balance);
            return;
        }

        ERC20 token = ERC20(_token);
        uint balance = token.balanceOf(this);
        token.transfer(address(msg.sender), balance);

        emit ClaimedTokens(_token, address(msg.sender), balance);
    }
}