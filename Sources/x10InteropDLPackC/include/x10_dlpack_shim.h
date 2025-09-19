#ifndef X10_DLPACK_SHIM_H
#define X10_DLPACK_SHIM_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

  typedef struct x10_dl_capsule
  {
    void *_opaque;
  } *x10_dl_capsule_t;

  // Availability & diagnostics
  int x10_dlpack_is_available(void);
  const char *x10_dlpack_last_error(void);

  // Lifecycle
  int x10_dlpack_dispose(x10_dl_capsule_t cap);

  // --- New: wrap/unwrap (host copy) -------------------------------------------
  // Wrap a host buffer into a DLManagedTensor (makes an owned copy).
  // Returns 1 on success, 0 on failure (x10_dlpack_last_error() will describe).
  int x10_dlpack_wrap_host_copy(
      const void *data,
      size_t nbytes,
      const int64_t *shape,
      int ndim,
      int32_t code,        // DLPack dtype code
      int32_t bits,        // dtype bit width
      int32_t lanes,       // dtype lanes (usually 1)
      int32_t device_type, // DLDeviceType
      int32_t device_id,   // device ordinal
      x10_dl_capsule_t *out_cap);

  // Copy tensor bytes from a capsule to host. If dst is NULL, writes the required
  // size to *written and returns 1.
  int x10_dlpack_to_host_copy(
      x10_dl_capsule_t cap,
      void *dst,
      size_t dst_size,
      size_t *written);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // X10_DLPACK_SHIM_H
