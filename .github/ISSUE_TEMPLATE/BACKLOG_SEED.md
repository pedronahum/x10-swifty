# Initial Backlog (copy/paste into GitHub issues)

1. Backend protocol skeleton
   - **Goal**: `Backend` with compile/execute/buffers/collectives/streams/events.
   - **Accept**: Compiles; PJRT and IREE stubs conform.

2. Device & Tensor façade
   - **Goal**: `Device` enum (+ default) and `Tensor<Scalar>` with shape + device.
   - **Accept**: Example builds and prints tensor.

3. Barrier semantics (`materialize()`)
   - **Goal**: Async API analogous to `LazyTensorBarrier()`.
   - **Accept**: Example awaits materialize successfully.

4. StableHLO builder stub
   - **Goal**: `IRBuilder` that returns a placeholder module; unit tests.
   - **Accept**: Golden text dump test placeholder.

5. PJRT backend shim
   - **Goal**: In-tree backend with stub methods; future C-API hooks.
   - **Accept**: Builds on macOS/Linux.

6. IREE backend placeholder
   - **Goal**: Structure mirrors PJRT; no core changes required.
   - **Accept**: Builds; no runtime behavior.

7. Diagnostics counters
   - **Goal**: `Diagnostics` counters for forced evals & uncached compiles.
   - **Accept**: Counters increment in a unit test.

8. CI workflow
   - **Goal**: GitHub Actions job using `swift-actions/setup-swift` and building example.
   - **Accept**: CI green on main.

9. README & CONTRIBUTING polish
   - **Goal**: Add architecture sketch and contribution guidance.
   - **Accept**: Docs merged.

10. Macro package bootstrap (follow-up)
    - **Goal**: Create `x10Macros` target with empty macros; no use in example yet.
    - **Accept**: Package compiles with macro toolchain.

