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

import { Script, console2 } from "forge-std/Script.sol";

import { TimelockCalldataGenerator, RateLimitConfig } from "../src/TimelockCalldataGenerator.sol";

/// @notice Invokes `TimelockCalldataGenerator` locally and prints the calldata for a
///         `Timelock.scheduleBatch(...)` call, without touching any network.
///
/// The generator is stateless (every function is `view`), so this script simply deploys a
/// fresh instance wired to the configured `Timelock` / `BeamState` addresses and forwards the
/// call. Only the `BeamState` address ends up embedded in the emitted calldata (it is the
/// `scheduleBatch` target); the `Timelock` address is the intended recipient of that calldata
/// and is not part of it, so it can be left unset when you only care about the payload.
///
/// Configure the addresses via environment variables (both default to the zero address):
///   - BEAM_STATE : address of the PAS `BeamState` (target of the scheduled batch)
///   - TIMELOCK   : address of the PAS `Timelock`  (recipient of the emitted calldata)
///
/// Pick the operation with `--sig`, matching a generator function's signature. Example:
///
///   forge script script/Generate.s.sol \
///     --sig "setHop(address,uint256,bytes32,bytes32,uint256)" \
///     $RATE_LIMITS 14400 $(cast 2b 0) $(cast keccak "spark-hop-2026-07") 172800
///
/// Array arguments (e.g. `bytes32[] ids`) are passed as `"[0x..,0x..]"`; struct/tuple arguments
/// (e.g. the `RateLimitConfig` for `addInitRateLimits`) as `"(0x..,0x..,1,2)"`.
contract Generate is Script {

    function _generator() internal returns (TimelockCalldataGenerator gen) {
        address beamState = vm.envOr("BEAM_STATE", address(0));
        require(beamState != address(0), "Generate/BEAM_STATE-not-set");
        gen = new TimelockCalldataGenerator(beamState);
        console2.log("beamState:", beamState);
    }

    function _print(bytes memory data) internal virtual {
        console2.log("calldata:");
        console2.logBytes(data);
    }

    // --- BeamState Configuration ---

    function start(bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().start(predecessor, salt, delay));
    }

    function setHop(address rateLimits, uint256 hop, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().setHop(rateLimits, hop, predecessor, salt, delay));
    }

    function setMaxChange(address rateLimits, uint256 maxChange, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().setMaxChange(rateLimits, maxChange, predecessor, salt, delay));
    }

    function addRateLimits(address rateLimits, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().addRateLimits(rateLimits, predecessor, salt, delay));
    }

    function addController(address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().addController(controller, predecessor, salt, delay));
    }

    function addCBeam(address cBeam, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().addCBeam(cBeam, predecessor, salt, delay));
    }

    function addInitRateLimits(RateLimitConfig calldata config, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().addInitRateLimits(config, predecessor, salt, delay));
    }

    function batchAddInitRateLimits(RateLimitConfig[] calldata configs, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().batchAddInitRateLimits(configs, predecessor, salt, delay));
    }

    // --- Roles Management Actions (through AccessControls) ---

    function grantRole(bytes32 role, address account, address accessControls, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().grantRole(role, account, accessControls, predecessor, salt, delay));
    }

    function revokeRole(bytes32 role, address account, address accessControls, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().revokeRole(role, account, accessControls, predecessor, salt, delay));
    }

    function setRoleAdmin(bytes32 role, bytes32 adminRole, address accessControls, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().setRoleAdmin(role, adminRole, accessControls, predecessor, salt, delay));
    }

    // --- Controller Actions (native functions) ---

    function updateIntegrations(bytes32[] calldata ids, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().updateIntegrations(ids, controller, predecessor, salt, delay));
    }

    function removeIntegrations(bytes32[] calldata ids, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().removeIntegrations(ids, controller, predecessor, salt, delay));
    }

    // --- Controller Actions (Diamond-PAU facets) ---

    function aave_setMaxSlippage(address aToken, uint256 maxSlippage, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().aave_setMaxSlippage(aToken, maxSlippage, controller, predecessor, salt, delay));
    }

    function cctp_setDomainParameters(uint32 destinationDomain, bytes32 recipient, uint32 minFeeCapRate, uint32 maxFeeCapRate, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().cctp_setDomainParameters(destinationDomain, recipient, minFeeCapRate, maxFeeCapRate, controller, predecessor, salt, delay));
    }

    function centrifuge_setRecipient(uint16 centrifugeId, bytes32 recipient, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().centrifuge_setRecipient(centrifugeId, recipient, controller, predecessor, salt, delay));
    }

    function curve_setMaxSlippage(address pool, uint256 maxSlippage, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().curve_setMaxSlippage(pool, maxSlippage, controller, predecessor, salt, delay));
    }

    function erc4626_setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().erc4626_setMaxExchangeRate(token, shares, maxExpectedAssets, controller, predecessor, salt, delay));
    }

    function layerZero_setRecipient(uint32 destinationEndpointId, bytes32 recipient, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().layerZero_setRecipient(destinationEndpointId, recipient, controller, predecessor, salt, delay));
    }

    function nfatHalo_setMaxAnnualGrowthRate(address facility, uint256 maxAnnualGrowthRate, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().nfatHalo_setMaxAnnualGrowthRate(facility, maxAnnualGrowthRate, controller, predecessor, salt, delay));
    }

    function otc_setMaxSlippage(address exchange, uint256 maxSlippage, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().otc_setMaxSlippage(exchange, maxSlippage, controller, predecessor, salt, delay));
    }

    function otc_setBuffer(address exchange, address buffer, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().otc_setBuffer(exchange, buffer, controller, predecessor, salt, delay));
    }

    function otc_setRechargeRate(address exchange, uint256 normalizedRate, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().otc_setRechargeRate(exchange, normalizedRate, controller, predecessor, salt, delay));
    }

    function uniswapV3_setMaxSlippage(address pool, uint256 maxSlippage, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().uniswapV3_setMaxSlippage(pool, maxSlippage, controller, predecessor, salt, delay));
    }

    function uniswapV3_setMaxTickDelta(address pool, uint24 maxTickDelta, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().uniswapV3_setMaxTickDelta(pool, maxTickDelta, controller, predecessor, salt, delay));
    }

    function uniswapV3_setLiquidityLowerTickBound(address pool, int24 lowerTickBound, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().uniswapV3_setLiquidityLowerTickBound(pool, lowerTickBound, controller, predecessor, salt, delay));
    }

    function uniswapV3_setLiquidityUpperTickBound(address pool, int24 upperTickBound, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().uniswapV3_setLiquidityUpperTickBound(pool, upperTickBound, controller, predecessor, salt, delay));
    }

    function uniswapV3_setTWAPSecondsAgo(address pool, uint32 twapSecondsAgo, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().uniswapV3_setTWAPSecondsAgo(pool, twapSecondsAgo, controller, predecessor, salt, delay));
    }

    function uniswapV4_setMaxSlippage(bytes32 poolId, uint256 maxSlippage, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().uniswapV4_setMaxSlippage(poolId, maxSlippage, controller, predecessor, salt, delay));
    }

    function uniswapV4_setTickLimits(bytes32 poolId, int24 tickLowerMin, int24 tickUpperMax, uint24 maxTickSpacing, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().uniswapV4_setTickLimits(poolId, tickLowerMin, tickUpperMax, maxTickSpacing, controller, predecessor, salt, delay));
    }

    function usds_setVault(address vault, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external {
        _print(_generator().usds_setVault(vault, controller, predecessor, salt, delay));
    }
}
