export IREE_SRC=$HOME/src/iree
export IREE_BUILD=$HOME/src/iree/build-macos-cpu
export IREE_INSTALL=$HOME/.local/iree-cpu

git clone --depth 1 https://github.com/iree-org/iree "$IREE_SRC"
cd "$IREE_SRC"
git submodule update --init

mkdir -p "$IREE_BUILD"
cd "$IREE_BUILD"

cmake -G Ninja -S "$IREE_SRC" -B "$IREE_BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$IREE_INSTALL" \
  -DIREE_BUILD_TESTS=OFF \
  -DIREE_BUILD_SAMPLES=OFF \
  -DIREE_BUILD_COMPILER=ON \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DIREE_TARGET_BACKEND_DEFAULTS=OFF \
  -DIREE_TARGET_BACKEND_LLVM_CPU=ON \
  -DIREE_HAL_DRIVER_DEFAULTS=OFF \
  -DIREE_HAL_DRIVER_LOCAL_SYNC=ON \
  -DIREE_HAL_DRIVER_LOCAL_TASK=ON

cmake --build "$IREE_BUILD" --target install --config Release -- -v

export X10_IREE_PREFIX="$IREE_INSTALL"
export X10_IREE_BIN="$X10_IREE_PREFIX/bin/iree-compile"
export X10_IREE_LIB="$(ls "$X10_IREE_PREFIX"/lib/*iree*runtime*.dylib 2>/dev/null | head -n1)"
