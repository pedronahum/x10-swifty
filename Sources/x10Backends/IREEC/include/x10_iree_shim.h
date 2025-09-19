#ifndef X10_IREE_SHIM_H
#define X10_IREE_SHIM_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

  // Availability & diagnostics
  int x10_iree_is_available(void); // 1 if compiled with IREE headers (flag), else 0
  int x10_iree_is_real(void);      // 1 if a real runtime path is active (later)
  const char *x10_iree_last_error(void);

  // Lifecycle (no-op/stub today; will create/destroy instances/devices later)
  int x10_iree_load(const char *explicit_path); // optional dynamic load
  void x10_iree_unload(void);

  // Compilation/Execution (stubs today)
  // Compile StableHLO text to an IREE module artifact (e.g., .vmfb bytes).
  // Returns 1 on success; writes the number of bytes needed into *out_size
  // if out_data == NULL. Otherwise copies up to out_capacity and writes *out_size.
  int x10_iree_compile_stablehlo_to_vmfb(
      const char *stablehlo_text,
      int32_t text_len,
      const char *target_backend, // "metal", "vulkan", "llvm-cpu", etc. (future)
      void *out_data,
      size_t out_capacity,
      size_t *out_size);

  // Execute a compiled artifact (not wired in stub yet).
  int x10_iree_execute_vmfb(
      const void *vmfb_data,
      size_t vmfb_size,
      int32_t device_ordinal);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // X10_IREE_SHIM_H
