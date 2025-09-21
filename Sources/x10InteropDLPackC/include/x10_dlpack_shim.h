#ifndef X10_DLPACK_SHIM_H
#define X10_DLPACK_SHIM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

  // Opaque capsule handle
  typedef struct x10_dl_capsule x10_dl_capsule;
  typedef x10_dl_capsule *x10_dl_capsule_t;

  // Availability/probe and last error string
  int x10_dlpack_is_available(void); // returns 1 if shim is compiled in
  const char *x10_dlpack_last_error(void);

  // ---- Zero-copy host alias (takes ownership of malloc'ed data) ----
  // Wrap a heap buffer (malloc/new) as a DLManagedTensor capsule; deleter will free(data).
  x10_dl_capsule_t x10_dlpack_wrap_host_buffer_free(
      void *data,
      const int64_t *shape, int32_t ndim,
      int32_t dtype_code, int32_t dtype_bits, int32_t dtype_lanes);

  // ---- Copy-based helpers (portable) ----
  // Copy `nbytes` from `bytes` into a newly-allocated tensor and return a capsule.
  // The device metadata is recorded (CPU, METAL, VULKAN, etc.), but data lives on host.
  int x10_dlpack_wrap_host_copy(
      const void *bytes, size_t nbytes,
      const int64_t *shape, int32_t ndim,
      int32_t dtype_code, int32_t dtype_bits, int32_t dtype_lanes,
      int32_t device_type, int32_t device_id,
      x10_dl_capsule_t *out_cap);

  // Copy tensor bytes into caller buffer. If `out==NULL` or `out_capacity==0`,
  // `*out_written` receives required number of bytes. Returns 1 on success.
  int x10_dlpack_to_host_copy(
      x10_dl_capsule_t cap,
      void *out, size_t out_capacity,
      int *out_written);

  // ---- Lifetime and queries ----
  x10_dl_capsule_t x10_dlpack_retain(x10_dl_capsule_t cap);
  void x10_dlpack_dispose(x10_dl_capsule_t cap);

  // Fill out tensor basics (device/dtype/ndim); returns 1 on success.
  int x10_dlpack_basic_info(
      x10_dl_capsule_t cap,
      int32_t *out_device_type, int32_t *out_device_id,
      int32_t *out_dtype_code, int32_t *out_dtype_bits, int32_t *out_dtype_lanes,
      int32_t *out_ndim);

  // Copy shape into `out_shape` if capacity >= ndim; returns ndim or -1 on failure.
  int x10_dlpack_shape(
      x10_dl_capsule_t cap, int64_t *out_shape, int32_t capacity);

  // Get data pointer and byte_offset; returns 1 on success.
  int x10_dlpack_data_ptr(
      x10_dl_capsule_t cap, void **out_ptr, size_t *out_byte_offset);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // X10_DLPACK_SHIM_H
