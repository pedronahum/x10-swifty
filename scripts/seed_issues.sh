#!/usr/bin/env bash
# Seed initial issues using GitHub CLI.
# Usage:
#   export REPO=pedronahum/x10-swifty
#   ./scripts/seed_issues.sh
set -euo pipefail
: "${REPO:?Set REPO to owner/name}"

# Ensure label exists
gh label create backlog --repo "$REPO" --color BFDADC --description "Planned items" 2>/dev/null || true

create() {
  local title="$1"
  local body="$2"
  gh issue create --repo "$REPO" -t "$title" -b "$body" --label "backlog"
}

create "Backend protocol skeleton" $'**Goal**: Define `Backend` with compile/execute/buffers/collectives/streams/events.\n**Acceptance**:\n- Types compile.\n- PJRT and IREE stubs conform.\n'
create "Device & Tensor façade" $'**Goal**: Implement `Device` and `Tensor<Scalar>` with shape + device.\n**Acceptance**:\n- Example builds and prints tensor.\n'
create "Barrier semantics (`materialize()`)" $'**Goal**: Async barrier analogous to `LazyTensorBarrier()`.\n**Acceptance**:\n- Example awaits `materialize()` successfully.\n'
create "StableHLO builder stub" $'**Goal**: `IRBuilder` returning a placeholder module; add unit tests.\n**Acceptance**:\n- Golden text dump test.\n'
create "PJRT backend shim" $'**Goal**: In-tree backend with stub methods; future C-API hooks.\n**Acceptance**:\n- Builds on macOS/Linux.\n'
create "IREE backend placeholder" $'**Goal**: Mirror PJRT structure; no core changes required.\n**Acceptance**:\n- Builds; no runtime behavior.\n'
create "Diagnostics counters" $'**Goal**: Counters for forced evals & uncached compiles.\n**Acceptance**:\n- Unit test increments counters.\n'
create "CI workflow" $'**Goal**: GitHub Actions job using `swift-actions/setup-swift`.\n**Acceptance**:\n- CI green on main.\n'
create "README & CONTRIBUTING polish" $'**Goal**: Add architecture sketch and contribution guidance.\n**Acceptance**:\n- Docs merged.\n'
create "Macro package bootstrap" $'**Goal**: Create `x10Macros` target with empty macros; not used yet.\n**Acceptance**:\n- Package compiles with macro toolchain.\n'
