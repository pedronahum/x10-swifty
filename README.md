# x10-swifty — A Swift‑first XLA/X10 playground with StableHLO, DLPack, PJRT & IREE

> **Goal.** A modern, Swifty façade for X10 ideas: Swift APIs + macros (future) that lower to StableHLO/MLIR and execute on multiple backends (PJRT, IREE), with zero‑copy interop and compile/run caching.

---

## What’s working today

**Core & Runtime**
- `Tensor<Element>` façade with shape/device metadata and a tiny StableHLO text IR builder for examples.
- `Device` & `DeviceScope` (`withDevice { … }`) + `X10_DEFAULT_DEVICE` env var (e.g. `gpu:0`).
- `JIT.compileCached(module:with:options:)` returns an `Executable` and caches by **(IR fingerprint, backend, device, options)**.
- `ExecutableCache` actor + **deterministic cache keys** (shape/device/backend/options).
- **Diagnostics** counters: `Diagnostics.uncachedCompiles`, `Diagnostics.forcedEvaluations`; basic “barrier” via `Tensor.materialize()` (simulates awaiting device work).

**Backends**
- **PJRT backend (stub)**: enumerates devices from env (`X10_PJRT_STUB_DEVICE_COUNT`), and implements `allocate`, `toDevice`, `fromDevice`. Good enough for exercising the runtime.
- **IREE backend (CLI path)**: 
  - Compiles StableHLO to `*.vmfb` using `iree-compile` (default target `llvm-cpu`).
  - Runs `*.vmfb` via `iree-run-module` and parses results for sanity tests.
  - A small in‑memory **VMFB registry** associates `Executable.id` → compiled blob so `execute` can shell out.
  - A resilient **signature rewriter** converts our textual StableHLO function header to IREE‑friendly MLIR (`tensor<…>` types).

**Interop**
- **DLPack (vendored)**: C shim (`x10InteropDLPackC`) + Swift wrapper (`x10InteropDLPack`).
  - Zero‑copy **host alias**: `DLPack.wrapHostBufferFree(ptr:shape:dtype:)` (capsule frees the malloc’d pointer).
  - Safe extractors: shape, dtype and data pointer helpers.
  - PJRT stub supports exporting buffers to DLPack capsules and round‑tripping.

**Tooling & Tests**
- Swift 6 toolchain; tests written with **swift‑testing**.
- Examples:
  - `x10ExampleBasics` – tiny tensor/IR demo
  - `x10ExampleIRCache` – shows compile cache identity
  - `x10ExamplePJRTDevices` – lists stub devices
  - `x10ExampleIREEAdd` – compiles & runs `add` via IREE CLI (optional)

---

## Quick start

### Requirements
- Swift 6 toolchain (recent 6.x dev snapshot recommended).
- macOS (Apple Silicon) tested. Linux should work for non‑IREE pieces with minor changes.

### Build & test
```bash
swift build
swift test
```

### Run examples
```bash
# Basics
swift run x10ExampleBasics

# IR + cache demo
swift run x10ExampleIRCache

# PJRT stub device discovery
swift run x10ExamplePJRTDevices
X10_PJRT_STUB_DEVICE_COUNT=4 swift run x10ExamplePJRTDevices
```

### IREE (optional, via CLI)
1) Install IREE (CPU) somewhere on your machine. For example:
```bash
# Example installation prefix (adjust to your paths)
export X10_IREE_PREFIX="$HOME/.local/iree-cpu"
export X10_IREE_BIN="$X10_IREE_PREFIX/bin/iree-compile"
export X10_IREE_RUN_BIN="$X10_IREE_PREFIX/bin/iree-run-module"
```
2) Run the example:
```bash
X10_BACKEND=iree \
X10_IREE_PREFIX="$HOME/.local/iree-cpu" \
X10_IREE_BIN="$HOME/.local/iree-cpu/bin/iree-compile" \
X10_IREE_RUN_BIN="$HOME/.local/iree-cpu/bin/iree-run-module" \
swift run x10ExampleIREEAdd
```
Typical output:
```
[IREE] compiled via /…/iree-compile (NNNN bytes)
IREE status: compileCLI=/…/iree-compile, runCLI=/…/iree-run-module, cached=NNNN bytes
--- IREE run (exit=0) ---
EXEC @main
result[0]: hal.buffer_view
2x3xf32=[5 7 9][8 10 12]
```

> You can override the IREE target backend with `X10_IREE_TARGET` (defaults to `llvm-cpu`).

#### Runtime vs CLI

The backend can execute entirely in-process via the IREE runtime shim. Enable it with:

```bash
X10_IREE_RUNTIME=1 swift run …
```

and/or pass `CompileOptions(flags: ["iree_runtime": "true"])` when compiling.
If the runtime shim fails to load, the backend gracefully falls back to the CLI runner.
Set `X10_IREE_DISABLE=1` to force the CLI path even when the runtime is present.

Diagnostics expose which path was used: `Diagnostics.executeCallsIreeRuntime` and
`Diagnostics.executeCallsIreeCLI` count each execution.

---

## Project layout

```
Sources/
  x10Core/                # Tensor façade, Device, PrecisionPolicy, StableHLO text helpers
  x10Runtime/             # JIT, ExecutableCache, Compilation, DeviceScope, Diagnostics
  x10Backends/
    PJRT/                 # PJRT stub Backend + buffer type
    IREE/                 # IREE backend (CLI compile/run) + ExecutableRegistry
  x10BackendsSelect/      # Backend picker (env/flags): PJRT vs IREE
  x10InteropDLPackC/      # C shim + vendored third_party/dlpack headers
  x10InteropDLPack/       # Swift DLPack wrapper (zero-copy host alias)
Examples/
  x10ExampleBasics/
  x10ExampleIRCache/
  x10ExamplePJRTDevices/
  x10ExampleIREEAdd/
Tests/                    # swift-testing suites for core/runtime/backends/interop
```

---

## Configuration knobs

- `X10_BACKEND=iree|pjrt` — choose backend (default heuristic prefers IREE if available).
- `X10_DEFAULT_DEVICE="cpu:0"|"gpu:0"` — default device for `DeviceScope` when caller does not set one.
- `X10_PJRT_STUB_DEVICE_COUNT=N` — number of stub “gpu” devices the PJRT shim should expose.
- `X10_IREE_PREFIX`, `X10_IREE_BIN`, `X10_IREE_RUN_BIN` — IREE locations for the CLI path.
- `X10_IREE_RUNTIME=1` — prefer the in-process runtime shim (falls back to CLI if unavailable).
- `X10_CACHE_MAX_ENTRIES=N` — cap the executable cache by entry count (default 256).
- `X10_CACHE_MAX_BYTES=N` — cap the executable cache by total VMFB bytes (default 64 MiB).
- `X10_IREE_TARGET=llvm-cpu|metal|vulkan-spirv` — target backend passed to `iree-compile`.
- `X10_IREE_VERBOSE=1` — log the MLIR and CLI calls during tests/examples.
- `withStrictBarriers { ... }` — helper to fail fast on accidental synchronous `materialize()` calls during async flows.

---

## How this maps to the original X10 ideas

- **Separation of concerns**: Swift APIs form a **front‑end façade** (`Tensor`, `@jit` planned), while backends (PJRT/IREE) implement execution.
- **Lazy values + barriers**: Ops build IR; `materialize()` acts as the **barrier** and increments diagnostics counters.
- **Polymorphism via shapes**: Cache keys incorporate dimensional shapes and device/backend to avoid megamorphism; roadmap includes **symbolic dims** bucketing.
- **Zero‑copy interop**: DLPack capsules allow aliasing host buffers without copies; this translates naturally to future device interop.

---

## Achievements (so far)

- ✅ Phase 0 **Definition complete**: public façade, barrier semantics, diagnostics, tests.
- ✅ PJRT **stub backend** + device/buffer protocol; round‑trip host bytes.
- ✅ **Executable cache** keyed by IR/device/backend/options (deterministic fingerprints).
- ✅ **DLPack** C shim + Swift wrapper; zero‑copy host alias integration with PJRT stub.
- ✅ **IREE (CLI)**: StableHLO → `.vmfb` compile + out‑of‑process run; signature rewriter; registry of VMFBs.
- ✅ **Backend picker** (`X10_BACKEND`) to route calls without changing user code.
- ✅ Examples and a healthy **test suite** (swift‑testing).

---

## What’s next (short‑term roadmap)

1. **IREE runtime C API (in‑process execution)**  
   Replace the CLI runner with calls into `iree_runtime_*`. Keep the CLI path behind a feature flag for debugging and for environments without dynamic libraries.

2. **Symbolic shapes & bucketing**  
   Add a `ShapeKey` that encodes known/unknown dims and bucket ranges; optional profiling to learn common shapes at runtime.

3. **Smarter cache**  
   - LRU with max entries and size thresholds.  
   - “Version salt” (invalidate on backend/compiler revs).  
   - **Cache warming** APIs to pre‑compile common shapes (vision/NLP).

4. **Strict barrier mode**  
   Async `materializeHost()` by default; add a strict mode that throws source‑mapped errors on accidental barriers in hot paths.

5. **Swifty `@jit` macros (exploratory)**  
   Syntax sugar to turn Swift functions into IR builders/call sites, with shape specialization hints.

6. **Edge/AOT first‑class**  
   Expand IREE target support for `metal`/`vulkan-spirv` and AOT flows. Embed `vmfb` blobs into Swift bundles for mobile/tvOS.

7. **PJRT evolution**  
   Keep the PJRT surface stable; later, wire an actual PJRT when practical (still optional; IREE will be the preferred edge path).

8. **Interop polish**  
   DLPack device capsules when a real backend is present; host/device zero‑copy transfers where possible.

---

## Open issues & planning

A (non‑exhaustive) snapshot of open issues in the tracker includes: **symbolic shapes**, **LRU cache & warming**, **strict barrier mode**, **IREE backend work**, **DLPack interop**, **macro package bootstrap**, **docs/CI polish**, and **StableHLO builder**. See the Issues tab for the full list and details.  

We group the work into:
- **Phase 1: Backends & Buffers** — finish PJRT surface, complete IREE (runtime API), solidify buffer protocols.
- **Phase 2: IR Builder & @jit** — macro sugar, richer ops, shape polymorphism, compile/runtime diagnostics.
- **Phase 3: Edge/AOT** — IREE AOT flows (Metal/Vulkan), asset embedding, modular backends, perf harness.

---

## Contributing

- Clone, build, and run tests as shown above.  
- If you have IREE installed, set the `X10_IREE_*` env vars to exercise optional examples/tests.  
- Please open an issue for proposals or pick up a “good first” item from the tracker.  
- Style: idiomatic Swift 6; prefer async APIs; keep public APIs Swifty (namespaced types, value semantics).

---

## License

This repository includes multiple components under their respective licenses. See `LICENSE` in the repo root and headers in `Sources/x10InteropDLPackC/include/third_party/dlpack`.

---

### Appendix — example: DLPack zero‑copy host alias (Swift)

```swift
import x10InteropDLPack
import x10Core

// 2x3 f32 host buffer we want to alias (no copy).
let host: [Float] = [1,2,3,4,5,6]
let nbytes = host.count * MemoryLayout<Float>.stride
let ptr = UnsafeMutableRawPointer.allocate(byteCount: nbytes, alignment: 64)
_ = host.withUnsafeBytes { src in
  memcpy(ptr, src.baseAddress!, src.count)
}

let cap = try DLPack.wrapHostBufferFree(ptr: ptr, shape: [2,3], dtype: .f32)
// pass `cap` across FFI or convert back to bytes for inspection:
let bytes = try DLPack.toHostBytes(cap)
```

---

**Have fun!** This is a learning/testing ground to make X10 concepts feel truly *Swifty* and pragmatic for modern ML/edge scenarios.



## Top priority

### P0 scope (what to do next, in small PR‑sized chunks)

#### P0.1 — Minimal IREE runtime shim (CPU first)

Add a guarded C target x10InteropIREEC that dynamically loads the IREE runtime library and wraps just what we need:

load a VMFB from bytes → runtime module handle

create a runtime instance + device (driver local-task for CPU)

create a context

prepare inputs/outputs (tensor→iree_hal_buffer_view)

invoke entry by name

read back outputs into host memory

Expose a tiny Swift wrapper IREEVM that mirrors those calls safely.

Acceptance: new test IREEBackendRuntimeExecuteTests (guarded by X10_IREE_RUNTIME=1) runs the add example end‑to‑end without spawning a process; all existing tests remain green.

#### P0.2 — Switch IREEBackend.execute to runtime (with CLI fallback)

In IREEBackend.execute, if X10_IREE_RUNTIME=1 (or CompileOptions.flags["iree_runtime"]=true):

Fetch VMFB bytes from IREEExecutableRegistry.

Load the module via the runtime wrapper.

Marshal inputs from Buffer → iree_hal_buffer_view (copy for CPU now).

Invoke, extract outputs, return Buffers (host‑backed for now).

Otherwise, keep the current CLI path. It’s great for debugging and for developers without the runtime libs installed.

Acceptance: runtime and CLI paths produce identical results for the add example (compare bytes).

#### P0.3 — Backend selection polish + diagnostics

Teach BackendPicker to prefer the runtime path if available: X10_BACKEND=iree + X10_IREE_RUNTIME=1.

Add Diagnostics.executeCalls{.ireeRuntime,.ireeCLI} counters so we can see what’s being exercised.

Update README with a short “runtime vs CLI” section and env toggles.

Acceptance: counters visible in tests; docs updated.

## P1 immediately after

LRU cache + version salt
Cap entries by count/bytes; add a salt (e.g., backend type + toolchain string) to invalidate stale execs automatically.

Symbolic shapes / bucketing (pragmatic first cut)
Let ShapeKey encode “known/dynamic” dims (Int?) and bucket ranges (e.g., 224–256) for common workloads. Emit deterministic fingerprints from IR + bucketing metadata.

Strict barrier mode
Keep materialize() async; add strict mode (env or option) that throws with a source‑mapped note when we sync in hot paths. Increment Diagnostics.forcedEvaluations.

## P2: edge & ergonomics

IREE Metal/Vulkan targets + AOT packaging:
Allow X10_IREE_TARGET=metal|vulkan-spirv; add a tiny tool to embed vmfb in app bundles (resources or Swift literals).

DLPack device capsules:
Once the runtime is in, add device‑side DLPack export/import for zero‑copy graphs between backends.

Swifty @jit macro (MVP):
Start with a macro that captures a Swift closure and emits the small StableHLO textual skeleton we already support, with shape annotations. Build out from there.
