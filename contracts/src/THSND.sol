// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// ---------------------------------------------------------------------
///  [ M U Y ]  —  Thousand Token — $THSND
///
///  Autonomous liquidity matrices. Fixed genesis supply. Burn-only.
///  one second, a thousand chances, it's a variable name.        // <- easter egg tier: comments only
/// ---------------------------------------------------------------------
///
///  Properties:
///   - 1,000,000,000 MUY minted once at genesis to the treasury. No mint function exists.
///   - Deflationary: `burn` / `burnFrom` reduce totalSupply forever; `totalBurned` is public.
///   - EIP-2612 permit for gasless approvals (frontend one-click flows).
///
///  This implementation is intentionally dependency-free for auditability.
///  It follows the OpenZeppelin ERC20/ERC20Permit storage layout and semantics;
///  swapping to OZ imports is a drop-in change if preferred.

contract THSND {
    // ---------------------------------------------------------------- ERC-20
    string public constant name = "Thousand";
    string public constant symbol = "THSND";
    uint8 public constant decimals = 18;

    uint256 public constant GENESIS_SUPPLY = 1_000_000_000e18;

    uint256 public totalSupply;
    uint256 public totalBurned;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // ---------------------------------------------------------------- EIP-2612
    mapping(address => uint256) public nonces;
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    uint256 private immutable INITIAL_CHAIN_ID;
    bytes32 private immutable INITIAL_DOMAIN_SEPARATOR;

    // ---------------------------------------------------------------- Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    /// @notice Emitted on every burn. The Matrix contracts (BurnEngine) watch this.
    event Burned(address indexed from, uint256 amount, uint256 newTotalSupply);

    constructor(address treasury) {
        require(treasury != address(0), "THSND: zero treasury");
        totalSupply = GENESIS_SUPPLY;
        balanceOf[treasury] = GENESIS_SUPPLY;
        emit Transfer(address(0), treasury, GENESIS_SUPPLY);

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
    }

    // ---------------------------------------------------------------- Core
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // ---------------------------------------------------------------- Burn (the only supply change possible)
    /// @notice Burn caller's tokens. Supply can only ever go down.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Burn from an account that approved the caller (used by BurnEngine).
    function burnFrom(address from, uint256 amount) external {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }

    // ---------------------------------------------------------------- Permit
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp <= deadline, "THSND: permit expired");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recovered = ecrecover(digest, v, r, s);
        require(recovered != address(0) && recovered == owner, "THSND: invalid signature");
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : _computeDomainSeparator();
    }

    // ---------------------------------------------------------------- Internal
    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "THSND: transfer to zero");
        uint256 bal = balanceOf[from];
        require(bal >= amount, "THSND: insufficient balance");
        unchecked {
            balanceOf[from] = bal - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 allowed = allowance[owner][spender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "THSND: insufficient allowance");
            unchecked {
                allowance[owner][spender] = allowed - amount;
            }
        }
    }

    function _burn(address from, uint256 amount) internal {
        uint256 bal = balanceOf[from];
        require(bal >= amount, "THSND: burn exceeds balance");
        unchecked {
            balanceOf[from] = bal - amount;
            totalSupply -= amount;
            totalBurned += amount;
        }
        emit Transfer(from, address(0), amount);
        emit Burned(from, amount, totalSupply);
    }

    function _computeDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }
}
