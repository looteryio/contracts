// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Lootery.sol";

contract LooteryMinter is Ownable {
    using SafeMath for uint256;

    uint256 constant MAX_TICKETS = 100_000;
    Lootery lootery;
    mapping(address => bool) operators;

    ERC20 immutable USDC;
    uint256 ticketPrice;

    modifier onlyAuthorized() {
        require(owner() == msg.sender || operators[msg.sender], "!authorized");
        _;
    }

    constructor(
        address _looteryAddress,
        ERC20 _usdc,
        uint256 _ticketPrice
    ) {
        lootery = Lootery(payable(_looteryAddress));
        USDC = _usdc;
        ticketPrice = _ticketPrice;
    }

    function toggleOperator(address _operator, bool _authorized)
        public
        onlyOwner
    {
        operators[_operator] = _authorized;
    }

    function transferLooteryOwnership(address _newOwner) public onlyOwner {
        lootery.transferOwnership(_newOwner);
    }

    function mintMany(address _toAddress, uint256 _amount)
        public
        onlyAuthorized
    {
        uint256 max = maxMintable();
        if (_amount > max) {
            _amount = max;
        }
        for (uint256 index = 0; index < _amount; index++) {
            lootery.mintTo(_toAddress);
        }
    }

    function setTicketPrice(uint256 _price) external onlyOwner {
        ticketPrice = _price;
    }

    function buyMany(uint256 _amount) public {
        require(!lootery.maxSupplyReached(), "Sold out!");
        require(lootery.state() == Lootery.LooteryState.OPEN, "Closed!");

        uint256 max = maxMintable();
        if (_amount > max) {
            _amount = max;
        }
        uint256 totalPrice = _amount.mul(ticketPrice);
        USDC.transferFrom(msg.sender, address(lootery), totalPrice);

        for (uint256 index = 0; index < _amount; index++) {
            lootery.mintTo(msg.sender);
        }
    }

    function transferMany(address _toAddress, uint256 _amount) public {
        uint256 balance = lootery.balanceOf(msg.sender);
        if (_amount > balance) {
            _amount = balance;
        }
        for (uint256 index = 0; index < _amount; index++) {
            uint256 tokenId = lootery.tokenOfOwnerByIndex(msg.sender, index);
            lootery.transferFrom(msg.sender, _toAddress, tokenId);
        }
    }

    function maxMintable() public view returns (uint256) {
        return MAX_TICKETS - lootery.totalSupply();
    }

    // Owner can drain tokens sent here
    function withdraw(address _token) public onlyOwner {
        IERC20 token = IERC20(_token);
        uint256 amount = token.balanceOf(address(this));
        token.transfer(msg.sender, amount);
    }

    function withdrawFromLootery(address _token) external onlyOwner {
        lootery.withdraw(_token);
        withdraw(_token);
    }

    function requestRandomNumber() external onlyOwner {
        lootery.requestRandomNumber();
    }

    function drawWinners() external onlyOwner {
        lootery.drawWinners();
    }
}
