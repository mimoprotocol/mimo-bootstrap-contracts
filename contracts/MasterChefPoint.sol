// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libraries/SignedSafeMath.sol";

contract MasterChefPoint is Ownable {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    /// @notice Info of each user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of Point entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    /// @notice Info of each pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of Point to distribute per block.
    struct PoolInfo {
        uint128 accPointPerShare;
        uint64 lastRewardBlock;
        uint64 allocPoint;
    }

    /// @notice Info of each pool.
    PoolInfo[] public poolInfo;
    /// @notice Address of the LP token for each pool.
    IERC20[] public lpToken;

    /// @notice Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    uint256 public pointPerBlock;
    uint256 public startBlock;
    uint256 public terminateBlock;

    uint256 private constant ACC_POINT_PRECISION = 1e12;

    event Deposit(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event Withdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event LogPoolAddition(
        uint256 indexed pid,
        uint256 allocPoint,
        IERC20 indexed lpToken
    );
    event LogSetPool(uint256 indexed pid, uint256 allocPoint);
    event LogUpdatePool(
        uint256 indexed pid,
        uint64 lastRewardBlock,
        uint256 lpSupply,
        uint256 accPointPerShare
    );

    constructor(uint256 _pointPerBlock) {
        pointPerBlock = _pointPerBlock;
    }

    /// @notice Returns the number of pools.
    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param allocPoint AP of the new pool.
    /// @param _lpToken Address of the LP ERC-20 token.
    function add(uint256 allocPoint, IERC20 _lpToken) public onlyOwner {
        if (terminateBlock > 0) {
            require(
                terminateBlock > block.number,
                "MasterChefPoint: farm have closed"
            );
        }

        uint256 lastRewardBlock = block.number;
        totalAllocPoint = totalAllocPoint.add(allocPoint);
        lpToken.push(_lpToken);

        poolInfo.push(
            PoolInfo({
                allocPoint: allocPoint.toUint64(),
                lastRewardBlock: lastRewardBlock.toUint64(),
                accPointPerShare: 0
            })
        );
        emit LogPoolAddition(lpToken.length.sub(1), allocPoint, _lpToken);
    }

    /// @notice Update the given pool's point allocation point. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOwner {
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint.toUint64();
        emit LogSetPool(_pid, _allocPoint);
    }

    /// @notice View function to see pending point on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending point reward for a given user.
    function pendingPoint(uint256 _pid, address _user)
        external
        view
        returns (uint256 pending)
    {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPointPerShare = pool.accPointPerShare;
        uint256 lpSupply = lpToken[_pid].balanceOf(address(this));

        uint256 endBlock = block.number;
        if (terminateBlock > 0 && terminateBlock <= endBlock) {
            endBlock = terminateBlock;
        }
        if (endBlock > pool.lastRewardBlock && lpSupply != 0) {
            uint256 blocks = endBlock.sub(pool.lastRewardBlock);
            uint256 pointReward = blocks.mul(pointPerBlock).mul(
                pool.allocPoint
            ) / totalAllocPoint;
            accPointPerShare = accPointPerShare.add(
                pointReward.mul(ACC_POINT_PRECISION) / lpSupply
            );
        }
        pending = int256(
            user.amount.mul(accPointPerShare) / ACC_POINT_PRECISION
        ).sub(user.rewardDebt)
        .toUInt256();
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    /// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    function massUpdatePools(uint256[] calldata pids) external {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(pids[i]);
        }
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        uint256 endBlock = block.number;
        if (terminateBlock > 0 && terminateBlock <= endBlock) {
            endBlock = terminateBlock;
        }
        if (pool.lastRewardBlock == endBlock) {
            return pool;
        }
        if (endBlock > pool.lastRewardBlock) {
            uint256 lpSupply = lpToken[pid].balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 blocks = endBlock.sub(pool.lastRewardBlock);
                uint256 pointReward = blocks.mul(pointPerBlock).mul(
                    pool.allocPoint
                ) / totalAllocPoint;
                pool.accPointPerShare =
                    pool.accPointPerShare +
                    (
                        (pointReward.mul(ACC_POINT_PRECISION) / lpSupply)
                        .toUint128()
                    );
            }
            pool.lastRewardBlock = endBlock.toUint64();
            poolInfo[pid] = pool;
            emit LogUpdatePool(
                pid,
                pool.lastRewardBlock,
                lpSupply,
                pool.accPointPerShare
            );
        }
    }

    /// @notice Deposit LP tokens for point allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(
        uint256 pid,
        uint256 amount,
        address to
    ) public {
        if (terminateBlock > 0) {
            require(
                terminateBlock > block.number,
                "MasterChefPoint: farm have closed"
            );
        }

        if (startBlock == 0) {
            startBlock = block.number;
        }

        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][to];

        // Effects
        user.amount = user.amount.add(amount);
        user.rewardDebt = user.rewardDebt.add(
            int256(amount.mul(pool.accPointPerShare) / ACC_POINT_PRECISION)
        );

        lpToken[pid].safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, pid, amount, to);
    }

    /// @notice Withdraw LP tokens.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdraw(
        uint256 pid,
        uint256 amount,
        address to
    ) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];

        // Effects
        user.rewardDebt = user.rewardDebt.sub(
            int256(amount.mul(pool.accPointPerShare) / ACC_POINT_PRECISION)
        );
        user.amount = user.amount.sub(amount);

        lpToken[pid].safeTransfer(to, amount);

        emit Withdraw(msg.sender, pid, amount, to);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(uint256 pid, address to) public {
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        // Note: transfer can fail or succeed if `amount` is zero.
        lpToken[pid].safeTransfer(to, amount);
        emit EmergencyWithdraw(msg.sender, pid, amount, to);
    }

    /// @notice Terminate farm.
    /// @param _terminateBlock The block number of termination.
    function terminate(uint256 _terminateBlock) external onlyOwner {
        require(
            _terminateBlock > block.number,
            "MasterChefPoint: invalid terminate block"
        );
        terminateBlock = _terminateBlock;
    }

    /// @notice View function to see user points on frontend.
    /// @param _user Address of user.
    /// @return points reward for a given user.
    function userPoints(address _user)
        external
        view
        returns (uint256 points)
    {
        uint256 endBlock = block.number;
        if (terminateBlock > 0 && terminateBlock <= endBlock) {
            endBlock = terminateBlock;
        }
        uint256 len = poolInfo.length;
        for (uint256 i = 0; i < len; ++i) {
            PoolInfo memory pool = poolInfo[i];
            UserInfo storage user = userInfo[i][_user];
            uint256 accPointPerShare = pool.accPointPerShare;
            uint256 lpSupply = lpToken[i].balanceOf(address(this));
            
            if (endBlock > pool.lastRewardBlock && lpSupply != 0) {
                uint256 blocks = endBlock.sub(pool.lastRewardBlock);
                uint256 pointReward = blocks.mul(pointPerBlock).mul(
                    pool.allocPoint
                ) / totalAllocPoint;
                accPointPerShare = accPointPerShare.add(
                    pointReward.mul(ACC_POINT_PRECISION) / lpSupply
                );
            }
            points += int256(
                user.amount.mul(accPointPerShare) / ACC_POINT_PRECISION
            ).sub(user.rewardDebt).toUInt256();
        }
    }

    function totalPoints() external view returns (uint256) {
        if (startBlock == 0) {
            return 0;
        }
        return (block.number - startBlock) * pointPerBlock;
    }
}
