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

interface TimelockLike {
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external;
}

interface BeamStateLike {
    function start() external;
    function setHop(address rateLimits_, uint256 value) external;
    function setMaxChange(address rateLimits_, uint256 value) external;
    function addRateLimits(address rateLimits_) external;
    function addController(address controller) external;
    function addCBeam(address cBeam) external;
    function addInitRateLimits(bytes32 key, address rateLimits_, uint256 maxAmount, uint256 slope) external;
    function addInitControllerActions(bytes calldata data, address controller) external returns (bytes32 key);
}

interface AccessControlsLike {
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;
}

// Controller-level admin selectors. The diamond wires each facet's function under a
// globally-unique controller-level selector (e.g. `aave_setMaxSlippage` rather than the
// bare `setMaxSlippage` that several facets share), so the generator emits calldata
// starting with those selectors and the diamond's fallback dispatches it to the right
// facet. These signatures are copied verbatim (only the ones this generator uses) from
// diamond-pau's `IMainnetControllerFull` (and IController for updateIntegrations/removeIntegrations);
// keep them in sync if a facet signature changes.
interface ControllerLike {
    function updateIntegrations(bytes32[] calldata ids) external;
    function removeIntegrations(bytes32[] calldata ids) external;
    function aave_setMaxSlippage(address aToken, uint256 maxSlippage) external;
    function cctp_setDomainParameters(uint32 destinationDomain, bytes32 recipient, uint32 minFeeCapRate, uint32 maxFeeCapRate) external;
    function centrifuge_setRecipient(uint16 centrifugeId, bytes32 recipient) external;
    function curve_setMaxSlippage(address pool, uint256 maxSlippage) external;
    function erc4626_setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets) external;
    function layerZero_setRecipient(uint32 destinationEndpointId, bytes32 recipient) external;
    function nfatHalo_setMaxAnnualGrowthRate(address facility, uint256 maxAnnualGrowthRate) external;
    function otc_setMaxSlippage(address exchange, uint256 maxSlippage) external;
    function otc_setBuffer(address exchange, address otcBuffer) external;
    function otc_setRechargeRate(address exchange, uint256 normalizedRate) external;
    function uniswapV3_setMaxSlippage(address pool, uint256 maxSlippage) external;
    function uniswapV3_setMaxTickDelta(address pool, uint24 maxTickDelta) external;
    function uniswapV3_setLiquidityLowerTickBound(address pool, int24 lowerTickBound) external;
    function uniswapV3_setLiquidityUpperTickBound(address pool, int24 upperTickBound) external;
    function uniswapV3_setTWAPSecondsAgo(address pool, uint32 twapSecondsAgo) external;
    function uniswapV4_setMaxSlippage(bytes32 poolId, uint256 maxSlippage) external;
    function uniswapV4_setTickLimits(bytes32 poolId, int24 tickLowerMin, int24 tickUpperMax, uint24 maxTickSpacing) external;
    function usds_setVault(address vault) external;
}

/// @notice Builds the calldata for scheduling PAS governance operations through the `Timelock`.
///
/// Usage is two-step:
///   1. Call the `pure` encoders below (`setHop`, `addController`, `grantRole`, `aave_setMaxSlippage`, …)
///      to get individual `BeamState` payloads.
///   2. Collect the payloads and pass them to `scheduleBatch`, which wraps them into the
///      `Timelock.scheduleBatch(...)` calldata a proposer submits on-chain (every payload targets
///      `BeamState`).
///
/// The contract holds no funds, has no privileged roles, and never mutates state.
contract TimelockCalldataGenerator {

    function _controllerActionPayload(bytes memory controllerData, address controller) internal pure returns (bytes memory payload) {
        payload = abi.encodeCall(BeamStateLike.addInitControllerActions, (controllerData, controller));
    }

    // --- Batch scheduling ---

    /// @notice Wrap `BeamState` payloads (as produced by the encoders below) into the calldata for
    ///         a single `Timelock.scheduleBatch(...)` operation. Every payload targets `beamState`.
    function scheduleBatch(
        address beamState,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external pure returns (bytes memory data) {
        uint256 len = payloads.length;

        address[] memory targets = new address[](len);
        for (uint256 i = 0; i < len; ++i) {
            targets[i] = beamState;
        }

        data = abi.encodeCall(TimelockLike.scheduleBatch, (targets, new uint256[](len), payloads, predecessor, salt, delay));
    }

    // --- BeamState Configuration ---

    function start() external pure returns (bytes memory payload) {
        payload = abi.encodeCall(BeamStateLike.start, ());
    }

    function setHop(address rateLimits, uint256 hop) external pure returns (bytes memory payload) {
        payload = abi.encodeCall(BeamStateLike.setHop, (rateLimits, hop));
    }

    function setMaxChange(address rateLimits, uint256 maxChange) external pure returns (bytes memory payload) {
        payload = abi.encodeCall(BeamStateLike.setMaxChange, (rateLimits, maxChange));
    }

    function addRateLimits(address rateLimits) external pure returns (bytes memory payload) {
        payload = abi.encodeCall(BeamStateLike.addRateLimits, (rateLimits));
    }

    function addController(address controller) external pure returns (bytes memory payload) {
        payload = abi.encodeCall(BeamStateLike.addController, (controller));
    }

    function addCBeam(address cBeam) external pure returns (bytes memory payload) {
        payload = abi.encodeCall(BeamStateLike.addCBeam, (cBeam));
    }

    function addInitRateLimits(bytes32 key, address rateLimits, uint256 maxAmount, uint256 slope) external pure returns (bytes memory payload) {
        payload = abi.encodeCall(BeamStateLike.addInitRateLimits, (key, rateLimits, maxAmount, slope));
    }

    // --- Roles Management Actions (through AccessControls) ---

    function grantRole(bytes32 role, address account, address accessControls) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(AccessControlsLike.grantRole, (role, account)), accessControls);
    }

    function revokeRole(bytes32 role, address account, address accessControls) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(AccessControlsLike.revokeRole, (role, account)), accessControls);
    }

    function setRoleAdmin(bytes32 role, bytes32 adminRole, address accessControls) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(AccessControlsLike.setRoleAdmin, (role, adminRole)), accessControls);
    }

    // --- Controller Actions (native functions) ---

    function updateIntegrations(bytes32[] calldata ids, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.updateIntegrations, (ids)), controller);
    }

    function removeIntegrations(bytes32[] calldata ids, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.removeIntegrations, (ids)), controller);
    }

    // --- Controller Actions (Diamond-PAU facets) ---

    // AaveFacet

    function aave_setMaxSlippage(address aToken, uint256 maxSlippage, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.aave_setMaxSlippage, (aToken, maxSlippage)), controller);
    }

    // CCTPFacet

    function cctp_setDomainParameters(
        uint32 destinationDomain,
        bytes32 recipient,
        uint32 minFeeCapRate,
        uint32 maxFeeCapRate,
        address controller
    ) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(
            abi.encodeCall(ControllerLike.cctp_setDomainParameters, (destinationDomain, recipient, minFeeCapRate, maxFeeCapRate)),
            controller
        );
    }

    // CentrifugeFacet

    function centrifuge_setRecipient(uint16 centrifugeId, bytes32 recipient, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.centrifuge_setRecipient, (centrifugeId, recipient)), controller);
    }

    // CurveFacet

    function curve_setMaxSlippage(address pool, uint256 maxSlippage, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.curve_setMaxSlippage, (pool, maxSlippage)), controller);
    }

    // ERC4626Facet

    function erc4626_setMaxExchangeRate(
        address token,
        uint256 shares,
        uint256 maxExpectedAssets,
        address controller
    ) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(
            abi.encodeCall(ControllerLike.erc4626_setMaxExchangeRate, (token, shares, maxExpectedAssets)),
            controller
        );
    }

    // LayerZeroFacet

    function layerZero_setRecipient(uint32 destinationEndpointId, bytes32 recipient, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.layerZero_setRecipient, (destinationEndpointId, recipient)), controller);
    }

    // NFATHaloFacet

    function nfatHalo_setMaxAnnualGrowthRate(address facility, uint256 maxAnnualGrowthRate, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.nfatHalo_setMaxAnnualGrowthRate, (facility, maxAnnualGrowthRate)), controller);
    }

    // OTCFacet

    function otc_setMaxSlippage(address exchange, uint256 maxSlippage, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.otc_setMaxSlippage, (exchange, maxSlippage)), controller);
    }

    function otc_setBuffer(address exchange, address buffer, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.otc_setBuffer, (exchange, buffer)), controller);
    }

    function otc_setRechargeRate(address exchange, uint256 normalizedRate, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.otc_setRechargeRate, (exchange, normalizedRate)), controller);
    }

    // UniswapV3Facet

    function uniswapV3_setMaxSlippage(address pool, uint256 maxSlippage, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.uniswapV3_setMaxSlippage, (pool, maxSlippage)), controller);
    }

    function uniswapV3_setMaxTickDelta(address pool, uint24 maxTickDelta, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.uniswapV3_setMaxTickDelta, (pool, maxTickDelta)), controller);
    }

    function uniswapV3_setLiquidityLowerTickBound(address pool, int24 lowerTickBound, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.uniswapV3_setLiquidityLowerTickBound, (pool, lowerTickBound)), controller);
    }

    function uniswapV3_setLiquidityUpperTickBound(address pool, int24 upperTickBound, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.uniswapV3_setLiquidityUpperTickBound, (pool, upperTickBound)), controller);
    }

    function uniswapV3_setTWAPSecondsAgo(address pool, uint32 twapSecondsAgo, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.uniswapV3_setTWAPSecondsAgo, (pool, twapSecondsAgo)), controller);
    }

    // UniswapV4Facet

    function uniswapV4_setMaxSlippage(bytes32 poolId, uint256 maxSlippage, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.uniswapV4_setMaxSlippage, (poolId, maxSlippage)), controller);
    }

    function uniswapV4_setTickLimits(
        bytes32 poolId,
        int24 tickLowerMin,
        int24 tickUpperMax,
        uint24 maxTickSpacing,
        address controller
    ) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(
            abi.encodeCall(ControllerLike.uniswapV4_setTickLimits, (poolId, tickLowerMin, tickUpperMax, maxTickSpacing)),
            controller
        );
    }

    // USDSFacet

    function usds_setVault(address vault, address controller) external pure returns (bytes memory payload) {
        payload = _controllerActionPayload(abi.encodeCall(ControllerLike.usds_setVault, (vault)), controller);
    }
}
