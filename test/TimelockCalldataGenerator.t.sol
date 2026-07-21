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

import "pas/dss-test/DssTest.sol";
import { MCD, DssInstance } from "pas/dss-test/MCD.sol";
import { TimelockCalldataGenerator } from "src/TimelockCalldataGenerator.sol";
import { Timelock } from "pas/timelock/Timelock.sol";
import { BeamState } from "pas/BeamState.sol";
import { Configurator } from "pas/Configurator.sol";
import { PASDeploy } from "pas/deploy/PASDeploy.sol";
import { PASInit } from "pas/deploy/PASInit.sol";
import { PASInstance } from "pas/deploy/PASInstance.sol";

import { Beacon }     from "diamond-pau/Beacon.sol";
import { PAUFactory } from "diamond-pau/PAUFactory.sol";

import { IAccessControls }         from "diamond-pau/interfaces/IAccessControls.sol";
import { IAccessControl }          from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IController }             from "diamond-pau/interfaces/IController.sol";
import { IEnumerableIntegrations } from "diamond-pau/interfaces/IEnumerableIntegrations.sol";

import { AaveFacet }       from "diamond-pau/facets/aave/AaveFacet.sol";
import { CCTPFacet }       from "diamond-pau/facets/cctp/CCTPFacet.sol";
import { CentrifugeFacet } from "diamond-pau/facets/centrifuge/CentrifugeFacet.sol";
import { CurveFacet }      from "diamond-pau/facets/curve/CurveFacet.sol";
import { ERC4626Facet }    from "diamond-pau/facets/erc4626/ERC4626Facet.sol";
import { LayerZeroFacet }  from "diamond-pau/facets/layer-zero/LayerZeroFacet.sol";
import { NFATHaloFacet }   from "diamond-pau/facets/nfat-halo/NFATHaloFacet.sol";
import { OTCFacet }        from "diamond-pau/facets/otc/OTCFacet.sol";
import { UniswapV3Facet }  from "diamond-pau/facets/uniswap-v3/UniswapV3Facet.sol";
import { UniswapV4Facet }  from "diamond-pau/facets/uniswap-v4/UniswapV4Facet.sol";
import { USDSFacet }       from "diamond-pau/facets/usds/USDSFacet.sol";

import { IMainnetControllerFull } from "diamond-pau-test/interfaces/IMainnetControllerFull.sol";

interface RateLimitsLike {
    function grantRole(bytes32 role, address account) external;
    function getRateLimitData(bytes32 key) external view returns (uint256, uint256, uint256, uint256);
}

contract TimelockCalldataGeneratorTest is DssTest {
    bytes32 constant PREDECESSOR = keccak256("PREDECESSOR");
    uint256 constant MIN_DELAY = 1 days;
    bytes32 constant OZ_DEFAULT_ADMIN_ROLE = bytes32(0);

    // --- PAS Instance ---
    BeamState                 beamState;
    Configurator              configurator;
    Timelock                  timelock;
    TimelockCalldataGenerator generator;

    // --- Diamond-pau ---
    Beacon beacon;
    PAUFactory factory;
    IAccessControls accessControls;
    address almProxy;
    RateLimitsLike rateLimits;
    IMainnetControllerFull controller;

    address pauseProxy;
    address coreCouncil;
    address cBeam;

    function setUp() public {
        pauseProxy  = makeAddr("pauseProxy");
        coreCouncil = makeAddr("coreCouncil");
        cBeam       = makeAddr("cBeam");

        PASInstance memory pas = PASDeploy.deploy(address(this), pauseProxy, MIN_DELAY);
        beamState    = BeamState(pas.beamState);
        configurator = Configurator(pas.configurator);
        timelock     = Timelock(payable(pas.timelock));
        beacon       = new Beacon(address(this));
        factory      = new PAUFactory(address(beacon));
        generator    = new TimelockCalldataGenerator();

        accessControls = IAccessControls(factory.deployAccessControls(address(this)));
        almProxy       = factory.deployALMProxy(address(this));
        rateLimits     = RateLimitsLike(factory.deployRateLimits(address(this)));
        controller     = IMainnetControllerFull(payable(
            factory.deployController(address(accessControls), almProxy, address(rateLimits))
        ));

        accessControls.grantRole(OZ_DEFAULT_ADMIN_ROLE, address(configurator));
        rateLimits.grantRole(OZ_DEFAULT_ADMIN_ROLE, address(configurator));

        // Wire the subset of facets the generator targets.
        bytes32[] memory ids = new bytes32[](11);
        ids[0]  = _wireAaveFacet();
        ids[1]  = _wireCCTPFacet();
        ids[2]  = _wireCentrifugeFacet();
        ids[3]  = _wireCurveFacet();
        ids[4]  = _wireERC4626Facet();
        ids[5]  = _wireLayerZeroFacet();
        ids[6]  = _wireNFATHaloFacet();
        ids[7]  = _wireOTCFacet();
        ids[8]  = _wireUniswapV3Facet();
        ids[9]  = _wireUniswapV4Facet();
        ids[10] = _wireUSDSFacet();
        IController(payable(address(controller))).updateIntegrations(ids);

        vm.startPrank(pauseProxy);
        PASInit.init(pas, MIN_DELAY, coreCouncil, new address[](0), new address[](0));
        vm.stopPrank();

        // Onboard diamond controller, accessControls, rate limiters, and cBeam in BeamState via generator+timelock
        _execute(_scheduleOne(generator.addController(address(controller)),     bytes32(0), keccak256("ctrl")));
        _execute(_scheduleOne(generator.addController(address(accessControls)), bytes32(0), keccak256("ac")));
        _execute(_scheduleOne(generator.addRateLimits(address(rateLimits)),     bytes32(0), keccak256("rl")));
        _execute(_scheduleOne(generator.addCBeam(cBeam),                        bytes32(0), keccak256("cbeam")));

        // Verify generator-driven calls correctly configured BeamState
        assertEq(beamState.controllers(address(controller)),     1, "diamond controller not added");
        assertEq(beamState.controllers(address(accessControls)), 1, "diamond accessControls not added");
        assertEq(beamState.rateLimits(address(rateLimits)),      1, "rateLimits not added");
        assertEq(beamState.cBeams(cBeam),                        1, "cBeam not added");

        // Link cBeam to controllers / rate limiters
        vm.startPrank(coreCouncil);
        beamState.setCBeamForController(address(controller), cBeam);
        beamState.setCBeamForController(address(accessControls), cBeam);
        beamState.setCBeamForRateLimits(address(rateLimits), cBeam);
        vm.stopPrank();

        // Set hop for rate limiters (required for setRateLimit to work on increases)
        _execute(_scheduleOne(generator.setHop(address(rateLimits), 1 hours), bytes32(0), keccak256("rl-hop")));

        // Mark the shared predecessor as executed so every test's operations (which declare it as
        // their predecessor) can be executed.
        bytes32 slot = keccak256(abi.encode(PREDECESSOR, uint256(1))); // _timestamps is at slot 1
        vm.store(address(timelock), slot, bytes32(uint256(1))); // Executed == 1
        assertTrue(timelock.isOperationDone(PREDECESSOR));
    }

    // ============================================================================
    // Diamond-pau deployment / wiring
    // ============================================================================

    function _wireAaveFacet() internal returns (bytes32 id) {
        address facet = address(new AaveFacet());

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(IMainnetControllerFull.aave_setMaxSlippage.selector, AaveFacet.setMaxSlippage.selector);
        wires[1] = IEnumerableIntegrations.Wire(IMainnetControllerFull.aave_getMaxSlippage.selector, AaveFacet.getMaxSlippage.selector);

        id = "AAVE_FACET";
        beacon.setIntegration(id, IEnumerableIntegrations.Config({ facet: facet, wires: wires }));
    }

    function _wireCCTPFacet() internal returns (bytes32 id) {
        address facet = address(new CCTPFacet(makeAddr("CCTP_TOKEN_MESSENGER"), makeAddr("USDC")));

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(IMainnetControllerFull.cctp_setDomainParameters.selector, CCTPFacet.setDomainParameters.selector);
        wires[1] = IEnumerableIntegrations.Wire(IMainnetControllerFull.cctp_getDomainParameters.selector, CCTPFacet.getDomainParameters.selector);

        id = "CCTP_FACET";
        beacon.setIntegration(id, IEnumerableIntegrations.Config({ facet: facet, wires: wires }));
    }

    function _wireCentrifugeFacet() internal returns (bytes32 id) {
        address facet = address(new CentrifugeFacet());

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(IMainnetControllerFull.centrifuge_setRecipient.selector, CentrifugeFacet.setRecipient.selector);
        wires[1] = IEnumerableIntegrations.Wire(IMainnetControllerFull.centrifuge_getRecipient.selector, CentrifugeFacet.getRecipient.selector);

        id = "CENTRIFUGE_FACET";
        beacon.setIntegration(id, IEnumerableIntegrations.Config({ facet: facet, wires: wires }));
    }

    function _wireCurveFacet() internal returns (bytes32 id) {
        address facet = address(new CurveFacet());

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(IMainnetControllerFull.curve_setMaxSlippage.selector, CurveFacet.setMaxSlippage.selector);
        wires[1] = IEnumerableIntegrations.Wire(IMainnetControllerFull.curve_getMaxSlippage.selector, CurveFacet.getMaxSlippage.selector);

        id = "CURVE_FACET";
        beacon.setIntegration(id, IEnumerableIntegrations.Config({ facet: facet, wires: wires }));
    }

    function _wireERC4626Facet() internal returns (bytes32 id) {
        address facet = address(new ERC4626Facet());

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(IMainnetControllerFull.erc4626_setMaxExchangeRate.selector, ERC4626Facet.setMaxExchangeRate.selector);
        wires[1] = IEnumerableIntegrations.Wire(IMainnetControllerFull.erc4626_getMaxExchangeRate.selector, ERC4626Facet.getMaxExchangeRate.selector);

        id = "ERC4626_FACET";
        beacon.setIntegration(id, IEnumerableIntegrations.Config({ facet: facet, wires: wires }));
    }

    function _wireLayerZeroFacet() internal returns (bytes32 id) {
        address facet = address(new LayerZeroFacet());

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(IMainnetControllerFull.layerZero_setRecipient.selector, LayerZeroFacet.setRecipient.selector);
        wires[1] = IEnumerableIntegrations.Wire(IMainnetControllerFull.layerZero_getRecipient.selector, LayerZeroFacet.getRecipient.selector);

        id = "LAYER_ZERO_FACET";
        beacon.setIntegration(id, IEnumerableIntegrations.Config({ facet: facet, wires: wires }));
    }

    function _wireNFATHaloFacet() internal returns (bytes32 id) {
        address facet = address(new NFATHaloFacet());

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(IMainnetControllerFull.nfatHalo_setMaxAnnualGrowthRate.selector, NFATHaloFacet.setMaxAnnualGrowthRate.selector);
        wires[1] = IEnumerableIntegrations.Wire(IMainnetControllerFull.nfatHalo_getMaxAnnualGrowthRate.selector, NFATHaloFacet.getMaxAnnualGrowthRate.selector);

        id = "NFAT_HALO_FACET";
        beacon.setIntegration(id, IEnumerableIntegrations.Config({ facet: facet, wires: wires }));
    }

    function _wireOTCFacet() internal returns (bytes32 id) {
        address facet = address(new OTCFacet());

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](6);
        wires[0] = IEnumerableIntegrations.Wire(IMainnetControllerFull.otc_setMaxSlippage.selector,  OTCFacet.setMaxSlippage.selector);
        wires[1] = IEnumerableIntegrations.Wire(IMainnetControllerFull.otc_setBuffer.selector,       OTCFacet.setBuffer.selector);
        wires[2] = IEnumerableIntegrations.Wire(IMainnetControllerFull.otc_setRechargeRate.selector, OTCFacet.setRechargeRate.selector);
        wires[3] = IEnumerableIntegrations.Wire(IMainnetControllerFull.otc_getMaxSlippage.selector,  OTCFacet.getMaxSlippage.selector);
        wires[4] = IEnumerableIntegrations.Wire(IMainnetControllerFull.otc_getBuffer.selector,       OTCFacet.getBuffer.selector);
        wires[5] = IEnumerableIntegrations.Wire(IMainnetControllerFull.otc_getRechargeRate.selector, OTCFacet.getRechargeRate.selector);

        id = "OTC_FACET";
        beacon.setIntegration(id, IEnumerableIntegrations.Config({ facet: facet, wires: wires }));
    }

    function _wireUniswapV3Facet() internal returns (bytes32 id) {
        address facet = address(new UniswapV3Facet(makeAddr("UNISWAP_V3_POSITION_MGR"), makeAddr("UNISWAP_V3_ROUTER")));

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](9);
        wires[0] = IEnumerableIntegrations.Wire(IMainnetControllerFull.uniswapV3_setMaxSlippage.selector,             UniswapV3Facet.setMaxSlippage.selector);
        wires[1] = IEnumerableIntegrations.Wire(IMainnetControllerFull.uniswapV3_setMaxTickDelta.selector,            UniswapV3Facet.setMaxTickDelta.selector);
        wires[2] = IEnumerableIntegrations.Wire(IMainnetControllerFull.uniswapV3_setLiquidityLowerTickBound.selector, UniswapV3Facet.setLiquidityLowerTickBound.selector);
        wires[3] = IEnumerableIntegrations.Wire(IMainnetControllerFull.uniswapV3_setLiquidityUpperTickBound.selector, UniswapV3Facet.setLiquidityUpperTickBound.selector);
        wires[4] = IEnumerableIntegrations.Wire(IMainnetControllerFull.uniswapV3_setTWAPSecondsAgo.selector,          UniswapV3Facet.setTWAPSecondsAgo.selector);
        wires[5] = IEnumerableIntegrations.Wire(IMainnetControllerFull.uniswapV3_getMaxSlippage.selector,             UniswapV3Facet.getMaxSlippage.selector);
        wires[6] = IEnumerableIntegrations.Wire(IMainnetControllerFull.uniswapV3_getMaxTickDelta.selector,            UniswapV3Facet.getMaxTickDelta.selector);
        wires[7] = IEnumerableIntegrations.Wire(IMainnetControllerFull.uniswapV3_getLiquidityTickBounds.selector,     UniswapV3Facet.getLiquidityTickBounds.selector);
        wires[8] = IEnumerableIntegrations.Wire(IMainnetControllerFull.uniswapV3_getTWAPSecondsAgo.selector,          UniswapV3Facet.getTWAPSecondsAgo.selector);

        id = "UNISWAP_V3_FACET";
        beacon.setIntegration(id, IEnumerableIntegrations.Config({ facet: facet, wires: wires }));
    }

    function _wireUniswapV4Facet() internal returns (bytes32 id) {
        address facet = address(new UniswapV4Facet(makeAddr("PERMIT2"), makeAddr("UNISWAP_V4_POSITION_MGR"), makeAddr("UNISWAP_V4_ROUTER")));

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](4);
        wires[0] = IEnumerableIntegrations.Wire(IMainnetControllerFull.uniswapV4_setMaxSlippage.selector, UniswapV4Facet.setMaxSlippage.selector);
        wires[1] = IEnumerableIntegrations.Wire(IMainnetControllerFull.uniswapV4_setTickLimits.selector,  UniswapV4Facet.setTickLimits.selector);
        wires[2] = IEnumerableIntegrations.Wire(IMainnetControllerFull.uniswapV4_getMaxSlippage.selector, UniswapV4Facet.getMaxSlippage.selector);
        wires[3] = IEnumerableIntegrations.Wire(IMainnetControllerFull.uniswapV4_getTickLimits.selector,  UniswapV4Facet.getTickLimits.selector);

        id = "UNISWAP_V4_FACET";
        beacon.setIntegration(id, IEnumerableIntegrations.Config({ facet: facet, wires: wires }));
    }

    function _wireUSDSFacet() internal returns (bytes32 id) {
        address facet = address(new USDSFacet(makeAddr("USDS")));

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);
        wires[0] = IEnumerableIntegrations.Wire(IMainnetControllerFull.usds_setVault.selector, USDSFacet.setVault.selector);
        wires[1] = IEnumerableIntegrations.Wire(IMainnetControllerFull.usds_vault.selector,    USDSFacet.vault.selector);

        id = "USDS_FACET";
        beacon.setIntegration(id, IEnumerableIntegrations.Config({ facet: facet, wires: wires }));
    }

    // ============================================================================
    // Helpers
    // ============================================================================

    // Submits the generator-built calldata to the Timelock as coreCouncil (the proposer)
    // via a low-level call, and returns the id of the just-scheduled operation.
    function _scheduleWithGeneratorData(bytes memory data) internal returns (bytes32 id) {
        vm.prank(coreCouncil);
        (bool success, bytes memory ret) = address(timelock).call(data);
        if (!success) {
            if (ret.length > 0) {
                assembly { revert(add(32, ret), mload(ret)) }
            }
            revert("TimelockCalldataGenerator/schedule-call-failed");
        }
        id = timelock.getLastOperationId();
    }

    // Wraps a single generator payload into a scheduleBatch operation and submits it.
    function _scheduleOne(bytes memory payload, bytes32 predecessor, bytes32 salt) internal returns (bytes32 id) {
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = payload;
        id = _scheduleWithGeneratorData(generator.scheduleBatch(address(beamState), payloads, predecessor, salt, MIN_DELAY));
    }

    function _execute(bytes32 id) internal {
        vm.warp(block.timestamp + MIN_DELAY);
        Timelock.Operation memory op = timelock.getOperation(id);
        timelock.executeBatch(op.targets, op.values, op.payloads, op.predecessor, op.salt);
    }

    function _getControllerAction(bytes32 id) internal view returns (bytes memory data, address controller_) {
        Timelock.Operation memory op = timelock.getOperation(id);
        // Decode payload: selector (4 bytes) || abi.encode(data, controller)
        bytes memory payload = op.payloads[0];
        assembly {
            payload := add(payload, 4)
        }
        (data, controller_) = abi.decode(payload, (bytes, address));
    }

    function _expectedOperationId(bytes memory payload, bytes32 predecessor, bytes32 salt) internal view returns (bytes32) {
        address[] memory targets = new address[](1);
        targets[0] = address(beamState);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = payload;
        return timelock.hashOperationBatch(targets, values, payloads, predecessor, salt);
    }

    function _expectedControllerActionId(bytes memory controllerData, address controller_, bytes32 predecessor, bytes32 salt) internal view returns (bytes32) {
        return _expectedOperationId(
            abi.encodeWithSelector(BeamState.addInitControllerActions.selector, controllerData, controller_),
            predecessor,
            salt
        );
    }

    // Schedules + executes a generator-built controller action and routes it through the
    // configurator to the target controller. Returns the extracted controller-action data
    // for assertions.
    function _runControllerAction(bytes memory payload, bytes memory expectedControllerData, address target, bytes32 salt) internal returns (bytes memory data) {
        bytes32 expectedId = _expectedControllerActionId(expectedControllerData, target, PREDECESSOR, salt);

        bytes32 id = _scheduleOne(payload, PREDECESSOR, salt);
        assertEq(id, expectedId, "operation id mismatch");
        assertEq(timelock.getTimestamp(id), block.timestamp + MIN_DELAY);

        address ctrlAddr;
        (data, ctrlAddr) = _getControllerAction(id);
        assertEq(ctrlAddr, target, "controller mismatch");
        assertEq(data, expectedControllerData, "controller data mismatch");

        _execute(id);

        vm.prank(cBeam);
        configurator.callControllerAction(target, data);
    }

    // ============================================================================
    // BeamState Configuration Tests
    // ============================================================================

    function testStart() public {
        vm.prank(coreCouncil);
        beamState.stop();
        assertTrue(beamState.stopped());

        bytes32 salt = keccak256("start");
        bytes32 expectedId = _expectedOperationId(abi.encodeWithSelector(BeamState.start.selector), PREDECESSOR, salt);

        bytes32 id = _scheduleOne(generator.start(), PREDECESSOR, salt);
        assertEq(id, expectedId);
        assertEq(timelock.getTimestamp(id), block.timestamp + MIN_DELAY);
        _execute(id);
        assertFalse(beamState.stopped());
    }

    function testSetHop() public {
        bytes32 salt = keccak256("hop");
        bytes32 expectedId = _expectedOperationId(abi.encodeWithSelector(BeamState.setHop.selector, address(rateLimits), 1800), PREDECESSOR, salt);

        bytes32 id = _scheduleOne(generator.setHop(address(rateLimits), 1800), PREDECESSOR, salt);
        assertEq(id, expectedId);
        assertEq(timelock.getTimestamp(id), block.timestamp + MIN_DELAY);
        _execute(id);
        assertEq(beamState.getHop(address(rateLimits)), 1800);
    }

    function testSetMaxChange() public {
        bytes32 salt = keccak256("mc");
        bytes32 expectedId = _expectedOperationId(abi.encodeWithSelector(BeamState.setMaxChange.selector, address(rateLimits), 2e18), PREDECESSOR, salt);

        bytes32 id = _scheduleOne(generator.setMaxChange(address(rateLimits), 2e18), PREDECESSOR, salt);
        assertEq(id, expectedId);
        assertEq(timelock.getTimestamp(id), block.timestamp + MIN_DELAY);
        _execute(id);
        assertEq(beamState.maxChange(address(rateLimits)), 2e18);
    }

    function testAddRateLimits() public {
        address rateLimits_ = makeAddr("rateLimits");
        bytes32 salt = keccak256("rl");
        bytes32 expectedId = _expectedOperationId(abi.encodeWithSelector(BeamState.addRateLimits.selector, rateLimits_), PREDECESSOR, salt);

        bytes32 id = _scheduleOne(generator.addRateLimits(rateLimits_), PREDECESSOR, salt);
        assertEq(id, expectedId);
        assertEq(timelock.getTimestamp(id), block.timestamp + MIN_DELAY);
        _execute(id);
        assertEq(beamState.rateLimits(rateLimits_), 1);
    }

    function testAddController() public {
        address newController = makeAddr("controller");
        bytes32 salt = keccak256("ctrl");
        bytes32 expectedId = _expectedOperationId(abi.encodeWithSelector(BeamState.addController.selector, newController), PREDECESSOR, salt);

        bytes32 id = _scheduleOne(generator.addController(newController), PREDECESSOR, salt);
        assertEq(id, expectedId);
        assertEq(timelock.getTimestamp(id), block.timestamp + MIN_DELAY);
        _execute(id);
        assertEq(beamState.controllers(newController), 1);
    }

    function testAddCBeam() public {
        address beam = makeAddr("beam");
        bytes32 salt = keccak256("cbeam");
        bytes32 expectedId = _expectedOperationId(abi.encodeWithSelector(BeamState.addCBeam.selector, beam), PREDECESSOR, salt);

        bytes32 id = _scheduleOne(generator.addCBeam(beam), PREDECESSOR, salt);
        assertEq(id, expectedId);
        assertEq(timelock.getTimestamp(id), block.timestamp + MIN_DELAY);
        _execute(id);
        assertEq(beamState.cBeams(beam), 1);
    }

    function testAddInitRateLimits() public {
        bytes32 key = "deposit";
        uint256 maxAmount = 10_000_000e18;
        uint256 slope = 1_000_000e18;

        bytes32 salt = "init-rate-limits";

        bytes32 expectedId = _expectedOperationId(
            abi.encodeWithSelector(BeamState.addInitRateLimits.selector, key, address(rateLimits), maxAmount, slope),
            PREDECESSOR,
            salt
        );

        bytes32 id = _scheduleOne(generator.addInitRateLimits(key, address(rateLimits), maxAmount, slope), PREDECESSOR, salt);
        assertEq(id, expectedId);
        assertEq(timelock.getTimestamp(id), block.timestamp + MIN_DELAY);
        _execute(id);

        // Verify stored in BeamState
        BeamState.DefaultRateLimits memory limits = beamState.getInitRateLimits(key, address(rateLimits));
        assertEq(limits.maxAmount, maxAmount);
        assertEq(limits.slope, slope);

        // Execute on real rate limiter via Configurator
        vm.prank(cBeam);
        configurator.setRateLimit(address(rateLimits), key, maxAmount, slope);

        // Verify set on real rate limiter
        (uint256 setMax, uint256 setSlope,,) = rateLimits.getRateLimitData(key);
        assertEq(setMax, maxAmount);
        assertEq(setSlope, slope);
    }

    function testScheduleBatch() public {
        address newController = makeAddr("arbitraryController");
        address beam          = makeAddr("arbitraryCBeam");

        // A controller action to whitelist as part of the batch.
        bytes32 role    = keccak256("BATCH_ROLE");
        address account = makeAddr("batchRoleAccount");
        bytes memory controllerAction = abi.encodeCall(IAccessControl.grantRole, (role, account));

        // Collect several encoder payloads — including staging a controller action — and batch them
        // into one scheduled operation. scheduleBatch targets BeamState for every payload.
        bytes[] memory payloads = new bytes[](5);
        payloads[0] = generator.addController(newController);
        payloads[1] = generator.addCBeam(beam);
        payloads[2] = generator.grantRole(role, account, address(accessControls));
        payloads[3] = generator.addInitRateLimits("deposit", address(rateLimits), 5_000_000e18, 500_000e18);
        payloads[4] = generator.addInitRateLimits("withdraw", address(rateLimits), 3_000_000e18, 300_000e18);

        address[] memory targets = new address[](5);
        targets[0] = address(beamState);
        targets[1] = address(beamState);
        targets[2] = address(beamState);
        targets[3] = address(beamState);
        targets[4] = address(beamState);

        bytes32 salt = "schedule-batch";

        bytes32 expectedId = timelock.hashOperationBatch(targets, new uint256[](5), payloads, PREDECESSOR, salt);

        bytes32 id = _scheduleWithGeneratorData(generator.scheduleBatch(address(beamState), payloads, PREDECESSOR, salt, MIN_DELAY));
        assertEq(id, expectedId);
        assertEq(timelock.getTimestamp(id), block.timestamp + MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);
        timelock.executeBatch(targets, new uint256[](5), payloads, PREDECESSOR, salt);

        assertEq(beamState.controllers(newController), 1, "controller not added");
        assertEq(beamState.cBeams(beam),               1, "cBeam not added");
        assertTrue(
            beamState.isControllerActionEnabled(keccak256(controllerAction), address(accessControls)),
            "controller action not whitelisted"
        );
        assertEq(beamState.getInitRateLimits("deposit", address(rateLimits)).maxAmount, 5_000_000e18);
        assertEq(beamState.getInitRateLimits("withdraw", address(rateLimits)).maxAmount, 3_000_000e18);

        // The whitelisted action is now callable through the Configurator.
        vm.prank(cBeam);
        configurator.callControllerAction(address(accessControls), controllerAction);
        assertTrue(accessControls.hasRole(role, account), "role not granted via whitelisted action");

        // Execute on rate limiter via Configurator
        vm.startPrank(cBeam);
        configurator.setRateLimit(address(rateLimits), "deposit", 5_000_000e18, 500_000e18);
        configurator.setRateLimit(address(rateLimits), "withdraw", 3_000_000e18, 300_000e18);
        vm.stopPrank();

        // Verify set on rate limiter
        (uint256 max0, uint256 slope0,,) = rateLimits.getRateLimitData("deposit");
        assertEq(max0, 5_000_000e18);
        assertEq(slope0, 500_000e18);

        (uint256 max1, uint256 slope1,,) = rateLimits.getRateLimitData("withdraw");
        assertEq(max1, 3_000_000e18);
        assertEq(slope1, 300_000e18);
    }

    // ============================================================================
    // Roles Management Tests (through AccessControls)
    // ============================================================================

    function testGrantRole() public {
        bytes32 role    = keccak256("SOME_ROLE");
        address account = makeAddr("roleAccount");
        bytes32 salt    = keccak256("grant-role");

        assertFalse(accessControls.hasRole(role, account), "account already has role");

        bytes memory expected = abi.encodeCall(IAccessControl.grantRole, (role, account));
        _runControllerAction(
            generator.grantRole(role, account, address(accessControls)),
            expected,
            address(accessControls),
            salt
        );

        assertTrue(accessControls.hasRole(role, account), "role not granted");
    }

    function testRevokeRole() public {
        bytes32 role    = keccak256("SOME_ROLE");
        address account = makeAddr("roleAccount");
        bytes32 salt    = keccak256("revoke-role");

        // Grant the role first (test contract is the AccessControls admin).
        accessControls.grantRole(role, account);
        assertTrue(accessControls.hasRole(role, account), "role not granted for revoke setup");

        bytes memory expected = abi.encodeCall(IAccessControl.revokeRole, (role, account));
        _runControllerAction(
            generator.revokeRole(role, account, address(accessControls)),
            expected,
            address(accessControls),
            salt
        );

        assertFalse(accessControls.hasRole(role, account), "role not revoked");
    }

    function testSetRoleAdmin() public {
        bytes32 role      = keccak256("SOME_ROLE");
        bytes32 adminRole = keccak256("SOME_ADMIN_ROLE");
        bytes32 salt      = keccak256("set-role-admin");

        assertEq(accessControls.getRoleAdmin(role), OZ_DEFAULT_ADMIN_ROLE, "unexpected initial role admin");

        bytes memory expected = abi.encodeCall(IAccessControls.setRoleAdmin, (role, adminRole));
        _runControllerAction(
            generator.setRoleAdmin(role, adminRole, address(accessControls)),
            expected,
            address(accessControls),
            salt
        );

        assertEq(accessControls.getRoleAdmin(role), adminRole, "role admin not updated");
    }

    // ============================================================================
    // Integration Management Tests (updateIntegrations / removeIntegrations)
    // ============================================================================

    // Wires a fresh facet into the Beacon under `id` using a call selector that is not already
    // wired by any facet in setUp (so updateIntegrations can add it without a dispatch collision).
    function _wireExtraFacet(bytes32 id, bytes4 callSelector) internal returns (address facet) {
        facet = address(new AaveFacet());

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](1);
        wires[0] = IEnumerableIntegrations.Wire(callSelector, AaveFacet.getMaxSlippage.selector);

        beacon.setIntegration(id, IEnumerableIntegrations.Config({ facet: facet, wires: wires }));
    }

    function testUpdateIntegrations() public {
        bytes32 integrationId = "EXTRA_FACET";
        bytes4  callSelector  = bytes4(keccak256("extra_dummy_selector()"));
        bytes32 salt          = keccak256("update-integrations");

        // Register the new integration in the Beacon and confirm it isn't on the controller yet.
        address facet = _wireExtraFacet(integrationId, callSelector);
        assertEq(controller.getConfig(integrationId).facet, address(0), "integration already present");
        uint256 countBefore = controller.integrations().length;

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = integrationId;

        bytes memory expected = abi.encodeCall(IController.updateIntegrations, (ids));
        _runControllerAction(
            generator.updateIntegrations(ids, address(controller)),
            expected,
            address(controller),
            salt
        );

        assertEq(controller.getConfig(integrationId).facet, facet, "integration not added");
        assertEq(controller.integrations().length, countBefore + 1, "integration count not incremented");
        assertEq(controller.getDispatch(callSelector).facet, facet, "dispatch not wired");
    }

    function testRemoveIntegrations() public {
        // "USDS_FACET" was wired onto the controller in setUp.
        bytes32 integrationId = "USDS_FACET";
        bytes32 salt          = keccak256("remove-integrations");

        assertNotEq(controller.getConfig(integrationId).facet, address(0), "integration not present");
        uint256 countBefore = controller.integrations().length;
        bytes4  usdsSelector = IMainnetControllerFull.usds_setVault.selector;
        assertNotEq(controller.getDispatch(usdsSelector).facet, address(0), "dispatch not wired before removal");

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = integrationId;

        bytes memory expected = abi.encodeCall(IController.removeIntegrations, (ids));
        _runControllerAction(
            generator.removeIntegrations(ids, address(controller)),
            expected,
            address(controller),
            salt
        );

        assertEq(controller.getConfig(integrationId).facet, address(0), "integration not removed");
        assertEq(controller.integrations().length, countBefore - 1, "integration count not decremented");
        assertEq(controller.getDispatch(usdsSelector).facet, address(0), "dispatch not cleared");
    }

    // ============================================================================
    // Controller Action Tests (real diamond-pau facets)
    // ============================================================================

    // --- AaveFacet ---

    function testAave_setMaxSlippage() public {
        address aToken = makeAddr("aToken");
        uint256 slippage = 250;
        bytes32 salt = keccak256("aave-slip");

        bytes memory expected = abi.encodeCall(IMainnetControllerFull.aave_setMaxSlippage, (aToken, slippage));
        _runControllerAction(
            generator.aave_setMaxSlippage(aToken, slippage, address(controller)),
            expected,
            address(controller),
            salt
        );

        assertEq(controller.aave_getMaxSlippage(aToken), slippage);
    }

    // --- CCTPFacet ---

    function testCctp_setDomainParameters() public {
        uint32 domain = 6;
        bytes32 recipient = bytes32(uint256(uint160(makeAddr("cctp-recipient"))));
        uint32 minFeeCapRate = 10;
        uint32 maxFeeCapRate = 100;
        bytes32 salt = keccak256("cctp-dom");

        bytes memory expected = abi.encodeCall(
            IMainnetControllerFull.cctp_setDomainParameters,
            (domain, recipient, minFeeCapRate, maxFeeCapRate)
        );
        _runControllerAction(
            generator.cctp_setDomainParameters(domain, recipient, minFeeCapRate, maxFeeCapRate, address(controller)),
            expected,
            address(controller),
            salt
        );

        (bytes32 storedRecipient, uint32 storedMin, uint32 storedMax) = controller.cctp_getDomainParameters(domain);
        assertEq(storedRecipient, recipient);
        assertEq(storedMin, minFeeCapRate);
        assertEq(storedMax, maxFeeCapRate);
    }

    // --- CentrifugeFacet ---

    function testCentrifuge_setRecipient() public {
        uint16 centrifugeId = 1;
        bytes32 recipient = bytes32(uint256(uint160(makeAddr("centrifuge-recipient"))));
        bytes32 salt = keccak256("cent-recipient");

        bytes memory expected = abi.encodeCall(IMainnetControllerFull.centrifuge_setRecipient, (centrifugeId, recipient));
        _runControllerAction(
            generator.centrifuge_setRecipient(centrifugeId, recipient, address(controller)),
            expected,
            address(controller),
            salt
        );

        assertEq(controller.centrifuge_getRecipient(centrifugeId), recipient);
    }

    // --- CurveFacet ---

    function testCurve_setMaxSlippage() public {
        address pool = makeAddr("curve-pool");
        uint256 slippage = 150;
        bytes32 salt = keccak256("curve-slip");

        bytes memory expected = abi.encodeCall(IMainnetControllerFull.curve_setMaxSlippage, (pool, slippage));
        _runControllerAction(
            generator.curve_setMaxSlippage(pool, slippage, address(controller)),
            expected,
            address(controller),
            salt
        );

        assertEq(controller.curve_getMaxSlippage(pool), slippage);
    }

    // --- ERC4626Facet ---

    function testErc4626_setMaxExchangeRate() public {
        address token = makeAddr("sDAI");
        uint256 shares = 1e18;
        uint256 maxExpectedAssets = 1.1e18;
        bytes32 salt = keccak256("4626-rate");

        bytes memory expected = abi.encodeCall(
            IMainnetControllerFull.erc4626_setMaxExchangeRate,
            (token, shares, maxExpectedAssets)
        );
        _runControllerAction(
            generator.erc4626_setMaxExchangeRate(token, shares, maxExpectedAssets, address(controller)),
            expected,
            address(controller),
            salt
        );

        // ERC4626Facet stores the rate as (assets * 1e36) / shares, not the (shares, assets) pair.
        uint256 expectedRate = (1e36 * maxExpectedAssets) / shares;
        assertEq(controller.erc4626_getMaxExchangeRate(token), expectedRate);
    }

    // --- LayerZeroFacet ---

    function testLayerZero_setRecipient() public {
        uint32 endpointId = 111;
        bytes32 recipient = bytes32(uint256(uint160(makeAddr("lz-recipient"))));
        bytes32 salt = keccak256("lz-recipient");

        bytes memory expected = abi.encodeCall(IMainnetControllerFull.layerZero_setRecipient, (endpointId, recipient));
        _runControllerAction(
            generator.layerZero_setRecipient(endpointId, recipient, address(controller)),
            expected,
            address(controller),
            salt
        );

        assertEq(controller.layerZero_getRecipient(endpointId), recipient);
    }

    // --- NFATHaloFacet ---

    function testNfatHalo_setMaxAnnualGrowthRate() public {
        address facility = makeAddr("nfat-facility");
        uint256 maxAnnualGrowthRate = 0.1e18;
        bytes32 salt = keccak256("nfat-growth");

        bytes memory expected = abi.encodeCall(
            IMainnetControllerFull.nfatHalo_setMaxAnnualGrowthRate,
            (facility, maxAnnualGrowthRate)
        );
        _runControllerAction(
            generator.nfatHalo_setMaxAnnualGrowthRate(facility, maxAnnualGrowthRate, address(controller)),
            expected,
            address(controller),
            salt
        );

        assertEq(controller.nfatHalo_getMaxAnnualGrowthRate(facility), maxAnnualGrowthRate);
    }

    // --- OTCFacet ---

    function testOtc_setMaxSlippage() public {
        address exchange = makeAddr("otc-exchange");
        uint256 slippage = 100;
        bytes32 salt = keccak256("otc-slip");

        bytes memory expected = abi.encodeCall(IMainnetControllerFull.otc_setMaxSlippage, (exchange, slippage));
        _runControllerAction(
            generator.otc_setMaxSlippage(exchange, slippage, address(controller)),
            expected,
            address(controller),
            salt
        );

        assertEq(controller.otc_getMaxSlippage(exchange), slippage);
    }

    function testOtc_setBuffer() public {
        address exchange = makeAddr("exchange");
        address buffer   = makeAddr("buffer");
        bytes32 salt = keccak256("otc-buf");

        bytes memory expected = abi.encodeCall(IMainnetControllerFull.otc_setBuffer, (exchange, buffer));
        _runControllerAction(
            generator.otc_setBuffer(exchange, buffer, address(controller)),
            expected,
            address(controller),
            salt
        );

        assertEq(controller.otc_getBuffer(exchange), buffer);
    }

    function testOtc_setRechargeRate() public {
        address exchange = makeAddr("exchange-rr");
        uint256 normalizedRate = 1e18;
        bytes32 salt = keccak256("otc-rr");

        bytes memory expected = abi.encodeCall(IMainnetControllerFull.otc_setRechargeRate, (exchange, normalizedRate));
        _runControllerAction(
            generator.otc_setRechargeRate(exchange, normalizedRate, address(controller)),
            expected,
            address(controller),
            salt
        );

        assertEq(controller.otc_getRechargeRate(exchange), normalizedRate);
    }

    // --- UniswapV3Facet ---

    function testUniswapV3_setMaxSlippage() public {
        address pool = makeAddr("pool");
        uint256 slippage = 50;
        bytes32 salt = keccak256("v3-slip");

        bytes memory expected = abi.encodeCall(IMainnetControllerFull.uniswapV3_setMaxSlippage, (pool, slippage));
        _runControllerAction(
            generator.uniswapV3_setMaxSlippage(pool, slippage, address(controller)),
            expected,
            address(controller),
            salt
        );

        assertEq(controller.uniswapV3_getMaxSlippage(pool), slippage);
    }

    function testUniswapV3_setMaxTickDelta() public {
        address pool = makeAddr("pool");
        uint24 maxTickDelta = 1000;
        bytes32 salt = keccak256("v3-tickdelta");

        bytes memory expected = abi.encodeCall(IMainnetControllerFull.uniswapV3_setMaxTickDelta, (pool, maxTickDelta));
        _runControllerAction(
            generator.uniswapV3_setMaxTickDelta(pool, maxTickDelta, address(controller)),
            expected,
            address(controller),
            salt
        );

        assertEq(controller.uniswapV3_getMaxTickDelta(pool), maxTickDelta);
    }

    function testUniswapV3_setLiquidityLowerTickBound() public {
        address pool = makeAddr("pool");
        int24 lowerTickBound = -887220;
        bytes32 salt = keccak256("v3-lower");

        bytes memory expected = abi.encodeCall(IMainnetControllerFull.uniswapV3_setLiquidityLowerTickBound, (pool, lowerTickBound));
        _runControllerAction(
            generator.uniswapV3_setLiquidityLowerTickBound(pool, lowerTickBound, address(controller)),
            expected,
            address(controller),
            salt
        );

        (int24 storedLower,) = controller.uniswapV3_getLiquidityTickBounds(pool);
        assertEq(storedLower, lowerTickBound);
    }

    function testUniswapV3_setLiquidityUpperTickBound() public {
        address pool = makeAddr("pool");
        int24 upperTickBound = 887220;
        bytes32 salt = keccak256("v3-upper");

        bytes memory expected = abi.encodeCall(IMainnetControllerFull.uniswapV3_setLiquidityUpperTickBound, (pool, upperTickBound));
        _runControllerAction(
            generator.uniswapV3_setLiquidityUpperTickBound(pool, upperTickBound, address(controller)),
            expected,
            address(controller),
            salt
        );

        (, int24 storedUpper) = controller.uniswapV3_getLiquidityTickBounds(pool);
        assertEq(storedUpper, upperTickBound);
    }

    function testUniswapV3_setTWAPSecondsAgo() public {
        address pool = makeAddr("pool");
        uint32 twapSecondsAgo = 1800;
        bytes32 salt = keccak256("v3-twap");

        bytes memory expected = abi.encodeCall(IMainnetControllerFull.uniswapV3_setTWAPSecondsAgo, (pool, twapSecondsAgo));
        _runControllerAction(
            generator.uniswapV3_setTWAPSecondsAgo(pool, twapSecondsAgo, address(controller)),
            expected,
            address(controller),
            salt
        );

        assertEq(controller.uniswapV3_getTWAPSecondsAgo(pool), twapSecondsAgo);
    }

    // --- UniswapV4Facet ---

    function testUniswapV4_setMaxSlippage() public {
        bytes32 poolId = keccak256("v4-pool");
        uint256 slippage = 75;
        bytes32 salt = keccak256("v4-slip");

        bytes memory expected = abi.encodeCall(IMainnetControllerFull.uniswapV4_setMaxSlippage, (poolId, slippage));
        _runControllerAction(
            generator.uniswapV4_setMaxSlippage(poolId, slippage, address(controller)),
            expected,
            address(controller),
            salt
        );

        assertEq(controller.uniswapV4_getMaxSlippage(poolId), slippage);
    }

    function testUniswapV4_setTickLimits() public {
        bytes32 poolId = keccak256("v4-tick-pool");
        int24 tickLowerMin = -887220;
        int24 tickUpperMax = 887220;
        uint24 maxTickSpacing = 200;
        bytes32 salt = keccak256("v4-tick");

        bytes memory expected = abi.encodeCall(
            IMainnetControllerFull.uniswapV4_setTickLimits,
            (poolId, tickLowerMin, tickUpperMax, maxTickSpacing)
        );
        _runControllerAction(
            generator.uniswapV4_setTickLimits(poolId, tickLowerMin, tickUpperMax, maxTickSpacing, address(controller)),
            expected,
            address(controller),
            salt
        );

        (int24 storedLower, int24 storedUpper, uint24 storedSpacing) = controller.uniswapV4_getTickLimits(poolId);
        assertEq(storedLower, tickLowerMin);
        assertEq(storedUpper, tickUpperMax);
        assertEq(storedSpacing, maxTickSpacing);
    }

    // --- USDSFacet ---

    function testUsds_setVault() public {
        address vault = makeAddr("usds-vault");
        bytes32 salt = keccak256("usds-vault");

        bytes memory expected = abi.encodeCall(IMainnetControllerFull.usds_setVault, (vault));
        _runControllerAction(
            generator.usds_setVault(vault, address(controller)),
            expected,
            address(controller),
            salt
        );

        assertEq(controller.usds_vault(), vault);
    }
}
