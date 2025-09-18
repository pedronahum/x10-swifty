#ifndef X10_PJRT_SHIM_H
#define X10_PJRT_SHIM_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

#include "x10_pjrt_c_api_inc.h"

  // ===== Loader / availability =====
  int x10_pjrt_load(const char *explicit_path);
  void x10_pjrt_unload(void);
  const char *x10_pjrt_last_error(void);
  int x10_pjrt_is_available(void);

  // **NEW**: 1 if a real PJRT C API is loaded (not just the stub)
  int x10_pjrt_is_real(void);

  // ===== Simple device enumeration (stub for now) =====
  int32_t x10_pjrt_device_count(void);
  size_t x10_pjrt_device_description(int32_t index, char *buffer, size_t capacity);

  // ===== Opaque client handle =====
  typedef struct x10_pjrt_client x10_pjrt_client;
  typedef x10_pjrt_client *x10_pjrt_client_t;

  int x10_pjrt_client_create(x10_pjrt_client_t *out_client);
  void x10_pjrt_client_destroy(x10_pjrt_client_t client);
  int x10_pjrt_client_device_count(x10_pjrt_client_t client, int32_t *out_count);

  // ===== Opaque executable handle =====
  typedef struct x10_pjrt_executable x10_pjrt_executable;
  typedef x10_pjrt_executable *x10_pjrt_executable_t;

  int x10_pjrt_compile_stablehlo(x10_pjrt_client_t client,
                                 const char *stablehlo_text,
                                 size_t text_len,
                                 const char *options_json,
                                 x10_pjrt_executable_t *out_exec);
  void x10_pjrt_executable_destroy(x10_pjrt_executable_t exec);
  int x10_pjrt_execute(x10_pjrt_executable_t exec, int32_t device_ordinal);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // X10_PJRT_SHIM_H
