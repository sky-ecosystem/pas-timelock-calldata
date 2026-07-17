# PAS Timelock Calldata Generator

`TimelockCalldataGenerator` is a stateless helper contract that builds the calldata needed to
schedule PAS governance operations through the PAS `Timelock`. It works in two steps: the encoder
functions (`setHop`, `addController`, `grantRole`, `aave_setMaxSlippage`, …) each return a single
`BeamState` payload, and `scheduleBatch` collects those payloads into the ABI-encoded `bytes` for a
`Timelock.scheduleBatch(...)` call that a proposer then submits on-chain. Every function is
`view`/`pure`; the contract holds no funds, has no privileged roles, and never mutates state — it
only assembles calldata.

## Why

PAS configuration changes (onboarding controllers and rate limiters, tuning rate limits, managing
roles, and configuring diamond-pau controller facets) all have to pass through the `Timelock` as
scheduled batch operations. Hand-encoding those payloads — nested `addInitControllerActions`
wrappers, controller-level selectors, `scheduleBatch` arguments — is error-prone. This generator
centralizes the encoding so proposers get correct calldata from a single, well-typed function call.

## How it works

Each encoder returns a single `BeamState` payload; you collect the payloads you need and pass them
to `scheduleBatch`, which wraps them all into the calldata for one `Timelock.scheduleBatch(...)`
operation (every payload targets `BeamState`). The encoders come in two shapes:

1. **Direct BeamState configuration.** Functions like `start`, `setHop`, and `addController` return
   the calldata for the corresponding `BeamState` function directly.

2. **Staged controller actions.** Functions that target a controller (or `AccessControls`) encode
   the inner call and wrap it in `BeamState.addInitControllerActions(data, controller)`. Executing
   the operation enables the action in `BeamState`; a cBEAM later routes it to the target via
   `Configurator.callControllerAction`.

```
generator.<fn>(...) ─▶ payload ─┐
generator.<fn>(...) ─▶ payload ─┼─▶ generator.scheduleBatch(payloads, …) ─▶ scheduleBatch(...) calldata
generator.<fn>(...) ─▶ payload ─┘                                                     │
                                                          proposer submits ───────────┘
                                                                            │
                                                                            ▼
                                                   Timelock.scheduleBatch        (waits `delay`)
                                                                            │
                                                                            ▼
                                                   Timelock.executeBatch
                                                                            │
                                                                            ▼
                                    ┌───────────────────────────────────────┴───────────┐
                                    │                                                    │
                                    ▼                                                    ▼
                         BeamState.<config fn>              BeamState.addInitControllerActions(data, target)
                         (start, addController, …)                          │
                                                                            ▼  (later, by a cBEAM)
                                                         Configurator.callControllerAction(target, data)
                                                                            │
                                                                            ▼
                                                              Controller / AccessControls
```

`scheduleBatch` takes the `BeamState` address that every payload targets, followed by the payloads
and the standard Timelock scheduling parameters:

- `beamState` — the `BeamState` address every payload targets
- `predecessor` — operation that must be executed first (`bytes32(0)` for none)
- `salt` — disambiguates otherwise-identical operations
- `delay` — timelock delay (must be `>=` the Timelock minimum)

Encoders that stage a controller action additionally take the target address (`controller` or
`accessControls`).

## Deployment

```solidity
TimelockCalldataGenerator generator = new TimelockCalldataGenerator();
```

The contract is stateless; the target `BeamState` address is passed to `scheduleBatch` at call time.

## Generating calldata

`script/Generate.s.sol` is a thin [Foundry](https://book.getfoundry.sh/) script that inherits the
generator. Any generator function can be called with `--sig`, and forge prints the returned bytes
under `== Return ==` as `data: bytes 0x…`.

First, get the payload for each operation from an encoder:

```bash
forge script script/Generate.s.sol --sig "setHop(address,uint256)" $RATE_LIMITS 14400
```

Then pass the `BeamState` address, the collected payload(s), and the `Timelock` related parameters to `scheduleBatch` to produce the final calldata:

```bash
forge script script/Generate.s.sol \
  --sig "scheduleBatch(address,bytes[],bytes32,bytes32,uint256)" \
  $BEAM_STATE "[<payload1>,<payload2>,...]" $(cast 2b 0) $(cast keccak "spark-hop-2026-07") 172800
```

The encoder `--sig` is any function from the [reference](#function-reference) below. Pass array
arguments as `"[0x..,0x..]"`.

### Batch scheduling

| Function | Purpose |
| --- | --- |
| `scheduleBatch` | Wrap the collected encoder `payloads` (each targeting `BeamState`) into the calldata for one `Timelock.scheduleBatch(...)` operation |

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
