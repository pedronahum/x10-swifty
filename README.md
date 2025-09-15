# x10 (Modern Swifty)

A starter scaffold for a Swift-first, XLA/StableHLO-based runtime with a backend abstraction
that supports PJRT today and leaves space for an IREE backend later. This layout is intentionally
backend-agnostic at the *core* so we don't rewrite foundations when adding IREE.

> Key ideas come from the original x10 deep-dive: lazy JIT + explicit barrier, multi-device rules,
> mixed precision, dynamic-shape mitigation, and an "infinitely hackable" Swift surface.

## Packages & modules
- `x10Core`: Tensor façade, device model, StableHLO builder stub, executable cache.
- `x10Runtime`: Backend protocol, streams/events, collectives, barrier semantics.
- `x10Backends/PJRT`: Placeholder PJRT backend implementing the `Backend` protocol.
- `x10Backends/IREE`: Empty stub to be implemented later without core changes.
- `x10Diagnostics`: Counters, timers, and logging hooks.
- `x10Adapters/TFEager`: Eager fallback hooks (optional / Tier C fallback).
- `Examples/01-basics`: Minimal example that builds today.

## Build
```bash
swift build
swift run x10ExampleBasics
```

## Next
- Wire a real PJRT C-API bridge into `x10Backends/PJRT`.
- Fill the StableHLO builder in `x10Core/IR`.
- Add Swift macros (separate package) once the runtime seams are stable.
