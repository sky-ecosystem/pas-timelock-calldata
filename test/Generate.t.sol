// SPDX-FileCopyrightText: © 2026 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { Generate } from "../script/Generate.s.sol";
import { TimelockCalldataGenerator, RateLimitConfig } from "../src/TimelockCalldataGenerator.sol";

/// @dev Subclass that captures the bytes the script would otherwise only `console2.log`, so the
///      test can assert on them. `_generator()` still reads `BEAM_STATE` and deploys a real
///      generator, so every wrapper is exercised exactly as under `forge script`.
contract GenerateHarness is Generate {
    bytes public captured;

    function _print(bytes memory data) internal override {
        captured = data;
    }
}

/// @notice Verifies every `Generate` wrapper forwards its arguments to `TimelockCalldataGenerator`
///         intact, by comparing the script's output against a `ref` generator deployed directly
///         with the same `BeamState`. Since `beamState` is a random address and the comparison is
///         over the full calldata, a match also proves the script honours the `BEAM_STATE` env var
///         (a hardcoded or wrong address would not match). The generator is pure calldata encoding,
///         so no real BeamState (and no fork) is needed.
///
/// Note: `vm.setEnv` writes one process-global variable and Foundry runs test contracts
/// concurrently, so two contracts setting `BEAM_STATE` to different values race
/// non-deterministically. Every test here therefore agrees on a single `beamState`, and the
/// `require(beamState != address(0))` guard is intentionally NOT unit-tested — a sibling contract
/// setting `BEAM_STATE` to the zero address would flakily clobber (or be clobbered by) this one.
contract GenerateTest is Test {
    GenerateHarness           script;
    TimelockCalldataGenerator ref;

    // Distinct addresses/values so a wrong forwarding order would break the calldata match.
    address beamState      = makeAddr("beamState");
    address controller     = makeAddr("controller");
    address accessControls = makeAddr("accessControls");
    address rateLimits     = makeAddr("rateLimits");
    address pool           = makeAddr("pool");
    address exchange       = makeAddr("exchange");

    bytes32 constant PREDECESSOR = bytes32(0);
    bytes32 constant SALT        = keccak256("salt");
    uint256 constant DELAY       = 172800;

    function setUp() public {
        vm.setEnv("BEAM_STATE", vm.toString(beamState));

        script = new GenerateHarness();
        ref    = new TimelockCalldataGenerator(beamState);
    }

    // --- BeamState configuration ---

    function testStart() public {
        script.start(PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.start(PREDECESSOR, SALT, DELAY));
    }

    function testSetHop() public {
        script.setHop(rateLimits, 14400, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.setHop(rateLimits, 14400, PREDECESSOR, SALT, DELAY));
    }

    function testSetMaxChange() public {
        script.setMaxChange(rateLimits, 5000, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.setMaxChange(rateLimits, 5000, PREDECESSOR, SALT, DELAY));
    }

    function testAddRateLimits() public {
        script.addRateLimits(rateLimits, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.addRateLimits(rateLimits, PREDECESSOR, SALT, DELAY));
    }

    function testAddController() public {
        script.addController(controller, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.addController(controller, PREDECESSOR, SALT, DELAY));
    }

    function testAddCBeam() public {
        address cBeam = makeAddr("cBeam");
        script.addCBeam(cBeam, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.addCBeam(cBeam, PREDECESSOR, SALT, DELAY));
    }

    function testAddInitRateLimits() public {
        RateLimitConfig memory config = _config();
        script.addInitRateLimits(config, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.addInitRateLimits(config, PREDECESSOR, SALT, DELAY));
    }

    function testBatchAddInitRateLimits() public {
        RateLimitConfig[] memory configs = new RateLimitConfig[](2);
        configs[0] = _config();
        configs[1] = RateLimitConfig({
            key:        keccak256("rl-key-2"),
            rateLimits: makeAddr("rateLimits2"),
            maxAmount:  500_000e18,
            slope:      250e18
        });
        script.batchAddInitRateLimits(configs, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.batchAddInitRateLimits(configs, PREDECESSOR, SALT, DELAY));
    }

    // --- Roles management (through AccessControls) ---

    function testGrantRole() public {
        bytes32 role    = keccak256("SOME_ROLE");
        address account = makeAddr("account");
        script.grantRole(role, account, accessControls, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.grantRole(role, account, accessControls, PREDECESSOR, SALT, DELAY));
    }

    function testRevokeRole() public {
        bytes32 role    = keccak256("SOME_ROLE");
        address account = makeAddr("account");
        script.revokeRole(role, account, accessControls, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.revokeRole(role, account, accessControls, PREDECESSOR, SALT, DELAY));
    }

    function testSetRoleAdmin() public {
        bytes32 role      = keccak256("SOME_ROLE");
        bytes32 adminRole = keccak256("ADMIN_ROLE");
        script.setRoleAdmin(role, adminRole, accessControls, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.setRoleAdmin(role, adminRole, accessControls, PREDECESSOR, SALT, DELAY));
    }

    // --- Controller actions (native) ---

    function testUpdateIntegrations() public {
        bytes32[] memory ids = _ids();
        script.updateIntegrations(ids, controller, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.updateIntegrations(ids, controller, PREDECESSOR, SALT, DELAY));
    }

    function testRemoveIntegrations() public {
        bytes32[] memory ids = _ids();
        script.removeIntegrations(ids, controller, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.removeIntegrations(ids, controller, PREDECESSOR, SALT, DELAY));
    }

    // --- Controller actions (Diamond-PAU facets) ---

    function testAaveSetMaxSlippage() public {
        address aToken = makeAddr("aToken");
        script.aave_setMaxSlippage(aToken, 0.99e18, controller, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.aave_setMaxSlippage(aToken, 0.99e18, controller, PREDECESSOR, SALT, DELAY));
    }

    function testCctpSetDomainParameters() public {
        script.cctp_setDomainParameters(7, keccak256("recipient"), 100, 500, controller, PREDECESSOR, SALT, DELAY);
        assertEq(
            script.captured(),
            ref.cctp_setDomainParameters(7, keccak256("recipient"), 100, 500, controller, PREDECESSOR, SALT, DELAY)
        );
    }

    function testCentrifugeSetRecipient() public {
        script.centrifuge_setRecipient(42, keccak256("recipient"), controller, PREDECESSOR, SALT, DELAY);
        assertEq(
            script.captured(),
            ref.centrifuge_setRecipient(42, keccak256("recipient"), controller, PREDECESSOR, SALT, DELAY)
        );
    }

    function testCurveSetMaxSlippage() public {
        script.curve_setMaxSlippage(pool, 0.98e18, controller, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.curve_setMaxSlippage(pool, 0.98e18, controller, PREDECESSOR, SALT, DELAY));
    }

    function testErc4626SetMaxExchangeRate() public {
        address token = makeAddr("token");
        script.erc4626_setMaxExchangeRate(token, 1e18, 1.05e18, controller, PREDECESSOR, SALT, DELAY);
        assertEq(
            script.captured(),
            ref.erc4626_setMaxExchangeRate(token, 1e18, 1.05e18, controller, PREDECESSOR, SALT, DELAY)
        );
    }

    function testLayerZeroSetRecipient() public {
        script.layerZero_setRecipient(30101, keccak256("recipient"), controller, PREDECESSOR, SALT, DELAY);
        assertEq(
            script.captured(),
            ref.layerZero_setRecipient(30101, keccak256("recipient"), controller, PREDECESSOR, SALT, DELAY)
        );
    }

    function testNfatHaloSetMaxAnnualGrowthRate() public {
        address facility = makeAddr("facility");
        script.nfatHalo_setMaxAnnualGrowthRate(facility, 0.2e18, controller, PREDECESSOR, SALT, DELAY);
        assertEq(
            script.captured(),
            ref.nfatHalo_setMaxAnnualGrowthRate(facility, 0.2e18, controller, PREDECESSOR, SALT, DELAY)
        );
    }

    function testOtcSetMaxSlippage() public {
        script.otc_setMaxSlippage(exchange, 0.97e18, controller, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.otc_setMaxSlippage(exchange, 0.97e18, controller, PREDECESSOR, SALT, DELAY));
    }

    function testOtcSetBuffer() public {
        address buffer = makeAddr("buffer");
        script.otc_setBuffer(exchange, buffer, controller, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.otc_setBuffer(exchange, buffer, controller, PREDECESSOR, SALT, DELAY));
    }

    function testOtcSetRechargeRate() public {
        script.otc_setRechargeRate(exchange, 1e18, controller, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.otc_setRechargeRate(exchange, 1e18, controller, PREDECESSOR, SALT, DELAY));
    }

    function testUniswapV3SetMaxSlippage() public {
        script.uniswapV3_setMaxSlippage(pool, 0.995e18, controller, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.uniswapV3_setMaxSlippage(pool, 0.995e18, controller, PREDECESSOR, SALT, DELAY));
    }

    function testUniswapV3SetMaxTickDelta() public {
        script.uniswapV3_setMaxTickDelta(pool, 100, controller, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.uniswapV3_setMaxTickDelta(pool, 100, controller, PREDECESSOR, SALT, DELAY));
    }

    function testUniswapV3SetLiquidityLowerTickBound() public {
        script.uniswapV3_setLiquidityLowerTickBound(pool, -887220, controller, PREDECESSOR, SALT, DELAY);
        assertEq(
            script.captured(),
            ref.uniswapV3_setLiquidityLowerTickBound(pool, -887220, controller, PREDECESSOR, SALT, DELAY)
        );
    }

    function testUniswapV3SetLiquidityUpperTickBound() public {
        script.uniswapV3_setLiquidityUpperTickBound(pool, 887220, controller, PREDECESSOR, SALT, DELAY);
        assertEq(
            script.captured(),
            ref.uniswapV3_setLiquidityUpperTickBound(pool, 887220, controller, PREDECESSOR, SALT, DELAY)
        );
    }

    function testUniswapV3SetTWAPSecondsAgo() public {
        script.uniswapV3_setTWAPSecondsAgo(pool, 1800, controller, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.uniswapV3_setTWAPSecondsAgo(pool, 1800, controller, PREDECESSOR, SALT, DELAY));
    }

    function testUniswapV4SetMaxSlippage() public {
        bytes32 poolId = keccak256("poolId");
        script.uniswapV4_setMaxSlippage(poolId, 0.996e18, controller, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.uniswapV4_setMaxSlippage(poolId, 0.996e18, controller, PREDECESSOR, SALT, DELAY));
    }

    function testUniswapV4SetTickLimits() public {
        bytes32 poolId = keccak256("poolId");
        script.uniswapV4_setTickLimits(poolId, -887220, 887220, 60, controller, PREDECESSOR, SALT, DELAY);
        assertEq(
            script.captured(),
            ref.uniswapV4_setTickLimits(poolId, -887220, 887220, 60, controller, PREDECESSOR, SALT, DELAY)
        );
    }

    function testUsdsSetVault() public {
        address vault = makeAddr("vault");
        script.usds_setVault(vault, controller, PREDECESSOR, SALT, DELAY);
        assertEq(script.captured(), ref.usds_setVault(vault, controller, PREDECESSOR, SALT, DELAY));
    }

    // --- Helpers ---

    function _config() internal view returns (RateLimitConfig memory) {
        return RateLimitConfig({
            key:        keccak256("rl-key"),
            rateLimits: rateLimits,
            maxAmount:  1_000_000e18,
            slope:      1_000e18
        });
    }

    function _ids() internal pure returns (bytes32[] memory ids) {
        ids = new bytes32[](2);
        ids[0] = keccak256("integration-a");
        ids[1] = keccak256("integration-b");
    }
}
