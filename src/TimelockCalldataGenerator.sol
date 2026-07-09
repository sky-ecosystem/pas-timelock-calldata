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

    function hashOperationBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) external view returns (bytes32);
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

// Controller-level admin selectors. The diamond wires each facet's function under a
// globally-unique controller-level selector (e.g. `aave_setMaxSlippage` rather than the
// bare `setMaxSlippage` that several facets share), so the generator emits calldata
// starting with those selectors and the diamond's fallback dispatches it to the right
// facet. These signatures are copied verbatim (only the ones this generator uses) from
// diamond-pau's `IMainnetControllerFull`; keep them in sync if a facet signature changes.
interface ControllerLike {
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

struct RateLimitConfig {
    bytes32 key;
    address rateLimits;
    uint256 maxAmount;
    uint256 slope;
}

// Notes:
// - This generator is a helper only and can be bypassed by submitting payloads directly to the Timelock (for an authorised proposer).
// - The generator is assumed to be frequently replaced/improved, depending on downstream facet changes or other needs.
// - The actual downstream changes only take effect when cBEAMs use the BeamState configurations, so atomicity in configurations can not be assumed (which is a known issue).
// - As part of a controller onboarding it might need to be `kiss`ed on the PSM. That is assumed to be orchestrated without the generator.
contract TimelockCalldataGenerator {

    TimelockLike  public immutable timelock;
    BeamStateLike public immutable beamState;

    constructor(address timelock_, address beamState_) {
        timelock  = TimelockLike(payable(timelock_));
        beamState = BeamStateLike(beamState_);
    }

    function _encodeProposal(bytes memory payload, bytes32 predecessor, bytes32 salt, uint256 delay) internal view returns (bytes memory data) {
        address[] memory targets = new address[](1);
        targets[0] = address(beamState);
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = payload;
        data = abi.encodeCall(timelock.scheduleBatch, (targets, new uint256[](1), payloads, predecessor, salt, delay));
    }

    function _encodeControllerAction(bytes memory controllerData, address controller, bytes32 predecessor, bytes32 salt, uint256 delay) internal view returns (bytes memory data) {
        bytes memory payload = abi.encodeCall(BeamStateLike.addInitControllerActions, (controllerData, controller));
        data = _encodeProposal(payload, predecessor, salt, delay);
    }

    // --- BeamState Configuration ---

    function start(bytes32 predecessor, bytes32 salt, uint256 delay) external view returns (bytes memory data) {
        bytes memory payload = abi.encodeCall(BeamStateLike.start, ());
        data = _encodeProposal(payload, predecessor, salt, delay);
    }

    function setHop(address rateLimits, uint256 hop, bytes32 predecessor, bytes32 salt, uint256 delay) external view returns (bytes memory data) {
        bytes memory payload = abi.encodeCall(BeamStateLike.setHop, (rateLimits, hop));
        data = _encodeProposal(payload, predecessor, salt, delay);
    }

    function setMaxChange(address rateLimits, uint256 maxChange, bytes32 predecessor, bytes32 salt, uint256 delay) external view returns (bytes memory data) {
        bytes memory payload = abi.encodeCall(BeamStateLike.setMaxChange, (rateLimits, maxChange));
        data = _encodeProposal(payload, predecessor, salt, delay);
    }

    function addRateLimits(address rateLimits, bytes32 predecessor, bytes32 salt, uint256 delay) external view returns (bytes memory data) {
        bytes memory payload = abi.encodeCall(BeamStateLike.addRateLimits, (rateLimits));
        data = _encodeProposal(payload, predecessor, salt, delay);
    }

    function addController(address controller, bytes32 predecessor, bytes32 salt, uint256 delay) external view returns (bytes memory data) {
        bytes memory payload = abi.encodeCall(BeamStateLike.addController, (controller));
        data = _encodeProposal(payload, predecessor, salt, delay);
    }

    function addCBeam(address cBeam, bytes32 predecessor, bytes32 salt, uint256 delay) external view returns (bytes memory data) {
        bytes memory payload = abi.encodeCall(BeamStateLike.addCBeam, (cBeam));
        data = _encodeProposal(payload, predecessor, salt, delay);
    }

    function addInitRateLimits(
        RateLimitConfig calldata config,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory payload = abi.encodeCall(
            BeamStateLike.addInitRateLimits,
            (config.key, config.rateLimits, config.maxAmount, config.slope)
        );

        data = _encodeProposal(payload, predecessor, salt, delay);
    }

    function batchAddInitRateLimits(
        RateLimitConfig[] calldata configs,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        uint256 len = configs.length;

        address[] memory targets = new address[](len);
        bytes[] memory payloads = new bytes[](len);

        for (uint256 i = 0; i < len; ++i) {
            targets[i] = address(beamState);
            payloads[i] = abi.encodeCall(
                BeamStateLike.addInitRateLimits,
                (configs[i].key, configs[i].rateLimits, configs[i].maxAmount, configs[i].slope)
            );
        }
        data = abi.encodeCall(timelock.scheduleBatch, (targets, new uint256[](len), payloads, predecessor, salt, delay));
    }

    // --- Controller Actions (Diamond-PAU facets) ---

    // AaveFacet

    function aave_setMaxSlippage(
        address aToken,
        uint256 maxSlippage,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(ControllerLike.aave_setMaxSlippage, (aToken, maxSlippage));
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    // CCTPFacet

    function cctp_setDomainParameters(
        uint32 destinationDomain,
        bytes32 recipient,
        uint32 minFeeCapRate,
        uint32 maxFeeCapRate,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(
            ControllerLike.cctp_setDomainParameters,
            (destinationDomain, recipient, minFeeCapRate, maxFeeCapRate)
        );
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    // CentrifugeFacet

    function centrifuge_setRecipient(
        uint16 centrifugeId,
        bytes32 recipient,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(ControllerLike.centrifuge_setRecipient, (centrifugeId, recipient));
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    // CurveFacet

    function curve_setMaxSlippage(
        address pool,
        uint256 maxSlippage,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(ControllerLike.curve_setMaxSlippage, (pool, maxSlippage));
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    // ERC4626Facet

    function erc4626_setMaxExchangeRate(
        address token,
        uint256 shares,
        uint256 maxExpectedAssets,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(
            ControllerLike.erc4626_setMaxExchangeRate,
            (token, shares, maxExpectedAssets)
        );
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    // LayerZeroFacet

    function layerZero_setRecipient(
        uint32 destinationEndpointId,
        bytes32 recipient,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(
            ControllerLike.layerZero_setRecipient,
            (destinationEndpointId, recipient)
        );
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    // NFATHaloFacet

    function nfatHalo_setMaxAnnualGrowthRate(
        address facility,
        uint256 maxAnnualGrowthRate,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(
            ControllerLike.nfatHalo_setMaxAnnualGrowthRate,
            (facility, maxAnnualGrowthRate)
        );
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    // OTCFacet

    function otc_setMaxSlippage(
        address exchange,
        uint256 maxSlippage,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(ControllerLike.otc_setMaxSlippage, (exchange, maxSlippage));
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    function otc_setBuffer(
        address exchange,
        address buffer,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(ControllerLike.otc_setBuffer, (exchange, buffer));
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    function otc_setRechargeRate(
        address exchange,
        uint256 normalizedRate,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(ControllerLike.otc_setRechargeRate, (exchange, normalizedRate));
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    // UniswapV3Facet

    function uniswapV3_setMaxSlippage(
        address pool,
        uint256 maxSlippage,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(ControllerLike.uniswapV3_setMaxSlippage, (pool, maxSlippage));
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    function uniswapV3_setMaxTickDelta(
        address pool,
        uint24 maxTickDelta,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(ControllerLike.uniswapV3_setMaxTickDelta, (pool, maxTickDelta));
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    function uniswapV3_setLiquidityLowerTickBound(
        address pool,
        int24 lowerTickBound,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(
            ControllerLike.uniswapV3_setLiquidityLowerTickBound,
            (pool, lowerTickBound)
        );
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    function uniswapV3_setLiquidityUpperTickBound(
        address pool,
        int24 upperTickBound,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(
            ControllerLike.uniswapV3_setLiquidityUpperTickBound,
            (pool, upperTickBound)
        );
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    function uniswapV3_setTWAPSecondsAgo(
        address pool,
        uint32 twapSecondsAgo,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(
            ControllerLike.uniswapV3_setTWAPSecondsAgo,
            (pool, twapSecondsAgo)
        );
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    // UniswapV4Facet

    function uniswapV4_setMaxSlippage(
        bytes32 poolId,
        uint256 maxSlippage,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(ControllerLike.uniswapV4_setMaxSlippage, (poolId, maxSlippage));
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    function uniswapV4_setTickLimits(
        bytes32 poolId,
        int24 tickLowerMin,
        int24 tickUpperMax,
        uint24 maxTickSpacing,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(
            ControllerLike.uniswapV4_setTickLimits,
            (poolId, tickLowerMin, tickUpperMax, maxTickSpacing)
        );
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }

    // USDSFacet

    function usds_setVault(
        address vault,
        address controller,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external view returns (bytes memory data) {
        bytes memory controllerData = abi.encodeCall(ControllerLike.usds_setVault, (vault));
        data = _encodeControllerAction(controllerData, controller, predecessor, salt, delay);
    }
}
