// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

import "./ERC721Tradable.sol";

contract Lootery is ERC721Tradable, VRFConsumerBase {
    uint256 immutable MAX_TICKETS;
    uint256 immutable NUMBER_OF_WINNERS;

    enum LooteryState {
        OPEN,
        RANDOMNESS_REQUESTED,
        CALCULATING_WINNERS,
        CLOSED
    }

    bytes32 internal keyHash;
    uint256 internal fee;
    address internal adminAddress;
    string _baseTokenURI;

    uint256[] public winningTickets;
    mapping(uint256 => bool) extracted;
    uint256 public randomnessResponse;
    LooteryState public state = LooteryState.OPEN;
    uint256 ticketPrice;
    mapping(uint256 => bool) _prizeCollected;

    ERC20[] _allPrizes;
    ERC20 immutable USDC;

    event PrizeCollected(
        address winner,
        uint256 tokenId,
        IERC20 prize,
        uint256 amount
    );

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _maxTickets,
        uint256 _winners,
        uint256 _ticketPrice,
        ERC20 _usdc,
        ERC20[] memory _prizes
    )
        ERC721Tradable(_name, _symbol)
        VRFConsumerBase(
            0x3d2341ADb2D31f1c5530cDC622016af293177AE0, // VRF Coordinator
            0xb0897686c545045aFc77CF20eC7A532E3120E0F1 // LINK Token
        )
    {
        keyHash = 0xf86195cf7690c55907b2b611ebb7343a6f649bff128701cc542f0569e2c549da;
        fee = 0.0001 * 10**18; // 0.0001 LINK
        adminAddress = msg.sender;
        MAX_TICKETS = _maxTickets;
        NUMBER_OF_WINNERS = _winners;
        winningTickets = new uint256[](_winners);
        _allPrizes = _prizes;
        ticketPrice = _ticketPrice;

        USDC = _usdc;
    }

    function _mintTo(address _to) internal override {
        require(_currentTokenId < MAX_TICKETS, "Max supply reached");
        super._mintTo(_to);

        if (maxSupplyReached()) {
            _requestRandomNumber();
        }
    }

    function mintTo(address _to) public onlyOwner {
        _mintTo(_to);
    }

    function buyTicket() public {
        require(!maxSupplyReached(), "Sold out!");
        require(state == LooteryState.OPEN, "Closed!");
        USDC.transferFrom(msg.sender, address(this), ticketPrice);

        _mintTo(msg.sender);
    }

    function maxSupplyReached() public view returns (bool) {
        uint256 totalSupply = totalSupply();
        return totalSupply == MAX_TICKETS;
    }

    function setBaseTokenURI(string calldata URI) external onlyOwner {
        _baseTokenURI = URI;
    }

    function baseTokenURI() public view override returns (string memory) {
        return _baseTokenURI;
    }

    function setTicketPrice(uint256 _price) external onlyOwner {
        ticketPrice = _price;
    }

    function requestRandomNumber() external onlyOwner {
        require(state == LooteryState.OPEN, "!Open");
        _requestRandomNumber();
    }

    function _requestRandomNumber() private {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");
        state = LooteryState.RANDOMNESS_REQUESTED;
        requestRandomness(keyHash, fee);
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        randomnessResponse = randomness;     
        state = LooteryState.CALCULATING_WINNERS;          
    }
    
    function drawWinners() external onlyOwner {
        require(state == LooteryState.CALCULATING_WINNERS, "Invalid state");
        for (uint256 i = 0; i < NUMBER_OF_WINNERS; i++) {
            drawTicket(i);
        }
        state = LooteryState.CLOSED;
    }

    function drawTicket(uint256 ticketIndex) private {
        bool valid = false;
        uint256 i = ticketIndex;
        while (!valid) {
            uint256 randomNumber = uint256(
                keccak256(abi.encode(randomnessResponse, i++))
            );
            uint256 winningTicket = (randomNumber % MAX_TICKETS) + 1;
            if (!extracted[winningTicket]) {
                winningTickets[ticketIndex] = winningTicket;
                extracted[winningTicket] = true;
                valid = true;
            }
        }
    }

    receive() external payable {}

    function safeTransferEth(address to, uint256 value) external onlyOwner {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "TransferHelper: TRANSFER_FAILED");
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    // Owner can drain tokens sent here
    function withdraw(address _token) external onlyOwner {
        IERC20 token = IERC20(_token);
        uint256 amount = token.balanceOf(address(this));
        token.transfer(msg.sender, amount);
    }

    function withdrawPrize() external {
        require(state == LooteryState.CLOSED, "Not closed");
        for (uint256 index = 0; index < winningTickets.length; index++) {
            if (
                msg.sender == ownerOf(winningTickets[index]) &&
                !_prizeCollected[index]
            ) {
                ERC20 prizeToken = _allPrizes[index];
                uint256 decimals = prizeToken.decimals();
                uint256 amount = 1 * 10**decimals;
                _prizeCollected[index] = true;
                prizeToken.transfer(msg.sender, amount);
                emit PrizeCollected(
                    msg.sender,
                    winningTickets[index],
                    prizeToken,
                    amount
                );                
            }
        }
    }
}
