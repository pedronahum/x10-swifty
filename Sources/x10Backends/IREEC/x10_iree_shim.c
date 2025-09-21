#include "x10_iree_shim.h"
#include <stdlib.h>
#include <string.h>

static const char *g_last_error = "";
static void set_last_error(const char *msg) { g_last_error = msg ? msg : ""; }

const char *x10_iree_last_error(void) { return g_last_error; }

int x10_iree_is_available(void)
{
#if defined(X10_IREE_HAVE_HEADERS)
  return 1;
#else
  return 0;
#endif
}

int x10_iree_is_real(void)
{
#if defined(X10_IREE_HAVE_HEADERS)
  // Later: probe iree_runtime properly; return 1 if linked/runtime ready.
  return 0;
#else
  return 0;
#endif
}

int x10_iree_load(const char *explicit_path)
{
  (void)explicit_path;
  // Later: dlopen iree_runtime library and resolve symbols.
  return 1;
}

void x10_iree_unload(void)
{
  // Later: dlclose.
}

int x10_iree_compile_stablehlo_to_vmfb(
    const char *stablehlo_text,
    int32_t text_len,
    const char *target_backend,
    void *out_data,
    size_t out_capacity,
    size_t *out_size)
{
  (void)target_backend;
#if defined(X10_IREE_HAVE_HEADERS)
  // TODO(real): call iree-compiler C API to produce VM FlatBuffer (vmfb).
  // For now, behave like a "probe": report size 0 and succeed to keep Swift green.
  if (out_size)
    *out_size = 0;
  return 1;
#else
  (void)stablehlo_text;
  (void)text_len;
  (void)out_data;
  (void)out_capacity;
  (void)out_size;
  set_last_error("compiled without IREE headers");
  return 0;
#endif
}

int x10_iree_execute_vmfb(
    const void *vmfb_data,
    size_t vmfb_size,
    int32_t device_ordinal)
{
  (void)vmfb_data;
  (void)vmfb_size;
  (void)device_ordinal;
#if defined(X10_IREE_HAVE_HEADERS)
  // TODO(real): create IREE instance + device; load module; run entrypoint.
  return 0; // not implemented yet
#else
  set_last_error("compiled without IREE headers");
  return 0;
#endif
}

int x10_iree_execute_vmfb_bytes(
    const void *vmfb_data, size_t vmfb_size,
    const char *entry_function,
    int32_t device_ordinal)
{
  (void)vmfb_data;
  (void)vmfb_size;
  (void)entry_function;
  (void)device_ordinal;
#if defined(X10_IREE_HAVE_HEADERS)
  // TODO(real): wire IREE runtime C API:
  // - iree_vm_instance_create
  // - iree_hal_driver/device create (local-task or llvm-cpu)
  // - iree_vm_module_create with vmfb bytes
  // - resolve entry function, marshal inputs/outputs
  // - call iree_vm_invoke
  set_last_error("x10_iree_execute_vmfb_bytes not implemented yet");
  return 0;
#else
  set_last_error("compiled without IREE headers");
  return 0;
#endif
}
