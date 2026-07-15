# PAS Timelock Calldata Generator

`TimelockCalldataGenerator` is a stateless helper contract that builds the calldata needed to
schedule PAS governance operations through the PAS `Timelock`. Every function is `view`: it returns
the ABI-encoded `bytes` for a `Timelock.scheduleBatch(...)` call that a proposer then submits
on-chain. The contract holds no funds, has no privileged roles, and never mutates state — it only
assembles calldata.

## Why

PAS configuration changes (onboarding controllers and rate limiters, tuning rate limits, managing
roles, and configuring diamond-pau controller facets) all have to pass through the `Timelock` as
scheduled batch operations. Hand-encoding those payloads — nested `addInitControllerActions`
wrappers, controller-level selectors, `scheduleBatch` arguments — is error-prone. This generator
centralizes the encoding so proposers get correct calldata from a single, well-typed function call.

## How it works

The generator produces calldata for two shapes of operation:

1. **Direct BeamState configuration.** Functions like `start`, `setHop`, and `addController` encode
   a single payload that calls the corresponding `BeamState` function directly, then wrap it in
   `scheduleBatch`.

2. **Staged controller actions.** Functions that target a controller (or `AccessControls`) encode
   the inner call, wrap it in `BeamState.addInitControllerActions(data, controller)`, and then wrap
   *that* in `scheduleBatch`. Executing the operation enables the action in `BeamState`; a cBEAM
   later routes it to the target via `Configurator.callControllerAction`.

```
generator.<fn>(...) ──▶ returns scheduleBatch(...) calldata
                              │
   proposer submits ──────────┘
                              │
                              ▼
                     Timelock.scheduleBatch        (waits `delay`)
                              │
                              ▼
                     Timelock.executeBatch
                              │
                              ▼
              ┌───────────────┴─────────────────┐
              │                                 │
              ▼                                 ▼
   BeamState.<config fn>          BeamState.addInitControllerActions(data, target)
   (start, addController, …)                    │
                                                ▼  (later, by a cBEAM)
                                   Configurator.callControllerAction(target, data)
                                                │
                                                ▼
                                     Controller / AccessControls
```

Every function takes the standard Timelock scheduling parameters as trailing arguments:

- `predecessor` — operation that must be executed first (`bytes32(0)` for none)
- `salt` — disambiguates otherwise-identical operations
- `delay` — timelock delay (must be `>=` the Timelock minimum)

Functions that stage a controller action additionally take the target address (`controller` or
`accessControls`).

## Deployment

```solidity
TimelockCalldataGenerator generator = new TimelockCalldataGenerator(beamStateAddress);
```

The BeamState address is stored as an immutable and exposed via `beamState()`.

## Function reference

### BeamState configuration

| Function | Purpose |
| --- | --- |
| `start` | Un-stop `BeamState` |
| `setHop` | Set the rate-limit `hop` for a rate limiter |
| `setMaxChange` | Set the max relative change for a rate limiter |
| `addRateLimits` | Register a rate limiter |
| `addController` | Register a controller |
| `addCBeam` | Register a cBEAM |
| `addInitRateLimits` | Stage default rate-limit config for one key (`RateLimitConfig`) |
| `batchAddInitRateLimits` | Stage default rate-limit config for many keys in one batch |

### Roles management (through AccessControls)

| Function | Purpose |
| --- | --- |
| `grantRole` | Grant a role on an `AccessControls` contract |
| `revokeRole` | Revoke a role |
| `setRoleAdmin` | Set the admin role for a role |

### Controller integrations (native controller functions)

| Function | Purpose |
| --- | --- |
| `updateIntegrations` | Add/overwrite diamond-pau integrations by id |
| `removeIntegrations` | Remove diamond-pau integrations by id |

### Controller facet actions (diamond-pau)

Encoded with the controller-level selectors (e.g. `aave_setMaxSlippage`) that the diamond dispatches
to the correct facet:

- **Aave** — `aave_setMaxSlippage`
- **CCTP** — `cctp_setDomainParameters`
- **Centrifuge** — `centrifuge_setRecipient`
- **Curve** — `curve_setMaxSlippage`
- **ERC4626** — `erc4626_setMaxExchangeRate`
- **LayerZero** — `layerZero_setRecipient`
- **NFATHalo** — `nfatHalo_setMaxAnnualGrowthRate`
- **OTC** — `otc_setMaxSlippage`, `otc_setBuffer`, `otc_setRechargeRate`
- **UniswapV3** — `uniswapV3_setMaxSlippage`, `uniswapV3_setMaxTickDelta`, `uniswapV3_setLiquidityLowerTickBound`, `uniswapV3_setLiquidityUpperTickBound`, `uniswapV3_setTWAPSecondsAgo`
- **UniswapV4** — `uniswapV4_setMaxSlippage`, `uniswapV4_setTickLimits`
- **USDS** — `usds_setVault`

> The controller-level selectors are copied verbatim from diamond-pau's `IMainnetControllerFull`.
> Keep the `ControllerLike` interface in `TimelockCalldataGenerator.sol` in sync if a facet
> signature changes.

## Development

Built with [Foundry](https://book.getfoundry.sh/).

```bash
forge build          # compile
forge test           # run the test suite
```

The test suite (`test/TimelockCalldataGenerator.t.sol`) is a **fork test**: it deploys a full PAS +
diamond-pau stack against a mainnet fork and exercises every generator function end-to-end through
the real `Timelock`, `BeamState`, `Configurator`, and controller facets. It requires a mainnet RPC
endpoint:

```bash
export ETH_RPC_URL=<mainnet-rpc-url>
forge test
```
