#ifndef X10_IREE_RUNTIME_SHIM_H
#define X10_IREE_RUNTIME_SHIM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Forward declared opaque handle representing an in-process
// IREE instance+device+session configured for CPU execution.
typedef struct x10_iree_vm_s x10_iree_vm_t;

// Scalar element types supported by the shim.
typedef enum {
  X10_IREE_DTYPE_F16 = 0,
  X10_IREE_DTYPE_BF16 = 1,
  X10_IREE_DTYPE_F32 = 2,
  X10_IREE_DTYPE_F64 = 3,
  X10_IREE_DTYPE_I32 = 4,
  X10_IREE_DTYPE_I64 = 5,
} x10_iree_dtype_t;

// Simple tensor view used for passing host-backed buffers into the runtime.
typedef struct {
  x10_iree_dtype_t dtype;
  const int64_t *shape;
  int32_t rank;
  const void *data;
  size_t byte_length;
} x10_iree_runtime_tensor_t;

// Host-backed tensor result produced by an invocation. Ownership of the
// `shape` and `data` pointers is transferred to the caller; release with
// `x10_iree_runtime_free_results`.
typedef struct {
  x10_iree_dtype_t dtype;
  int32_t rank;
  int64_t *shape;
  void *data;
  size_t byte_length;
} x10_iree_runtime_result_t;

// Retrieves the last error message recorded by the shim. The returned pointer
// remains valid until the next shim call.
const char *x10_iree_runtime_last_error(void);

// Returns 1 if the shim was compiled with access to IREE headers, else 0.
int x10_iree_runtime_is_available(void);

// Attempts to dynamically load the IREE runtime library. Returns 1 on success.
// The optional |explicit_path| overrides environment or default search.
int x10_iree_runtime_load(const char *explicit_path);

// Unloads the runtime library (no-op if not loaded).
void x10_iree_runtime_unload(void);

// Creates a CPU (local-task) backed VM session from the provided VMFB bytes.
// On success returns 1 and sets |out_vm|.
int x10_iree_vm_create_from_vmfb(const void *vmfb_data, size_t vmfb_size,
                                 x10_iree_vm_t **out_vm);

// Releases resources held by the VM handle (safe to pass NULL).
void x10_iree_vm_destroy(x10_iree_vm_t *vm);

// Invokes an exported entry point by fully-qualified name. The caller provides
// an array of input tensors. Outputs are allocated by the shim and returned via
// |out_results| / |out_result_count|; release with
// `x10_iree_runtime_free_results`.
int x10_iree_vm_invoke(x10_iree_vm_t *vm, const char *entry_name,
                       const x10_iree_runtime_tensor_t *inputs,
                       int32_t input_count,
                       x10_iree_runtime_result_t **out_results,
                       int32_t *out_result_count);

// Releases output buffers previously returned by `x10_iree_vm_invoke`.
void x10_iree_runtime_free_results(x10_iree_runtime_result_t *results,
                                   int32_t result_count);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // X10_IREE_RUNTIME_SHIM_H
