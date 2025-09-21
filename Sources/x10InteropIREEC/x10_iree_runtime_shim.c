#include "x10_iree_runtime_shim.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(X10_IREE_HAVE_HEADERS)

#include <dlfcn.h>

#include "iree/base/api.h"

// Some IREE headers expect users to define the system allocator entry points
// via macros, but in this minimal shim we provide a tiny malloc-backed
// allocator instead.
static iree_status_t x10_allocator_ctl(
    void *self, iree_allocator_command_t command, const void *params,
    void **inout_ptr)
{
  (void)self;
  switch (command) {
    case IREE_ALLOCATOR_COMMAND_MALLOC:
    case IREE_ALLOCATOR_COMMAND_CALLOC:
    case IREE_ALLOCATOR_COMMAND_REALLOC: {
      if (!params || !inout_ptr) {
        return iree_status_from_code(IREE_STATUS_INVALID_ARGUMENT);
      }
      const iree_allocator_alloc_params_t *alloc_params = params;
      iree_host_size_t size = alloc_params->byte_length;
      if (size == 0) size = 1;
      void *existing = *inout_ptr;
      void *result = NULL;
      if (command == IREE_ALLOCATOR_COMMAND_REALLOC && existing) {
        result = realloc(existing, size);
      } else if (command == IREE_ALLOCATOR_COMMAND_CALLOC) {
        result = calloc(1, size);
      } else {
        result = malloc(size);
      }
      if (!result) {
        return iree_status_from_code(IREE_STATUS_RESOURCE_EXHAUSTED);
      }
      *inout_ptr = result;
      return iree_ok_status();
    }
    case IREE_ALLOCATOR_COMMAND_FREE: {
      if (inout_ptr && *inout_ptr) {
        free(*inout_ptr);
        *inout_ptr = NULL;
      }
      return iree_ok_status();
    }
    default:
      return iree_status_from_code(IREE_STATUS_UNIMPLEMENTED);
  }
}

static iree_allocator_t x10_allocator_system(void)
{
  iree_allocator_t allocator = {NULL, x10_allocator_ctl};
  return allocator;
}
#include "iree/hal/api.h"
#include "iree/hal/buffer_view.h"
#include "iree/hal/buffer_view_util.h"
#include "iree/modules/hal/types.h"
#include "iree/runtime/api.h"
#include "iree/vm/api.h"

// -----------------------------------------------------------------------------
// Error plumbing
// -----------------------------------------------------------------------------

static char g_last_error_buf[512] = "";
static const char *g_last_error = g_last_error_buf;

static void set_last_error(const char *msg)
{
  if (!msg) msg = "";
  size_t n = strlen(msg);
  if (n >= sizeof(g_last_error_buf)) n = sizeof(g_last_error_buf) - 1;
  memcpy(g_last_error_buf, msg, n);
  g_last_error_buf[n] = '\0';
}

static void set_last_errorf(const char *fmt, ...)
{
  va_list args;
  va_start(args, fmt);
  vsnprintf(g_last_error_buf, sizeof(g_last_error_buf), fmt, args);
  va_end(args);
  g_last_error = g_last_error_buf;
}

const char *x10_iree_runtime_last_error(void)
{
  return g_last_error;
}

// -----------------------------------------------------------------------------
// Dynamic symbol loading
// -----------------------------------------------------------------------------

struct runtime_symbols {
  void *handle;

  void (*iree_runtime_instance_options_initialize)(iree_runtime_instance_options_t *out_options);
  void (*iree_runtime_instance_options_use_all_available_drivers)(iree_runtime_instance_options_t *options);
  iree_status_t (*iree_runtime_instance_create)(const iree_runtime_instance_options_t *options,
                                                iree_allocator_t host_allocator,
                                                iree_runtime_instance_t **out_instance);
  void (*iree_runtime_instance_release)(iree_runtime_instance_t *instance);
  iree_allocator_t (*iree_runtime_instance_host_allocator)(const iree_runtime_instance_t *instance);
  iree_vm_instance_t *(*iree_runtime_instance_vm_instance)(const iree_runtime_instance_t *instance);
  iree_status_t (*iree_runtime_instance_try_create_default_device)(const iree_runtime_instance_t *instance,
                                                                   iree_string_view_t driver_name,
                                                                   iree_hal_device_t **out_device);

  void (*iree_runtime_session_options_initialize)(iree_runtime_session_options_t *out_options);
  iree_status_t (*iree_runtime_session_create_with_device)(const iree_runtime_instance_t *instance,
                                                           const iree_runtime_session_options_t *options,
                                                           iree_hal_device_t *device,
                                                           iree_allocator_t host_allocator,
                                                           iree_runtime_session_t **out_session);
  void (*iree_runtime_session_release)(iree_runtime_session_t *session);
  iree_hal_device_t *(*iree_runtime_session_device)(const iree_runtime_session_t *session);
  iree_hal_allocator_t *(*iree_runtime_session_device_allocator)(const iree_runtime_session_t *session);
  iree_status_t (*iree_runtime_session_append_bytecode_module_from_memory)(
      iree_runtime_session_t *session, iree_const_byte_span_t flatbuffer_data,
      iree_allocator_t flatbuffer_allocator);
  iree_status_t (*iree_runtime_session_call_by_name)(iree_runtime_session_t *session,
                                                     iree_string_view_t full_name,
                                                     iree_vm_list_t *inputs,
                                                     iree_vm_list_t *outputs);

  iree_status_t (*iree_vm_list_create)(iree_vm_type_def_t element_type,
                                       iree_host_size_t initial_capacity,
                                       iree_allocator_t allocator,
                                       iree_vm_list_t **out_list);
  void (*iree_vm_list_release)(iree_vm_list_t *list);
  iree_status_t (*iree_vm_list_push_ref_move)(iree_vm_list_t *list, iree_vm_ref_t *value);
  iree_host_size_t (*iree_vm_list_size)(const iree_vm_list_t *list);
  iree_hal_buffer_view_t *(*iree_vm_list_get_buffer_view_assign)(const iree_vm_list_t *list,
                                                                 iree_host_size_t i);

  iree_status_t (*iree_hal_buffer_view_allocate_buffer_copy)(
      iree_hal_device_t *device, iree_hal_allocator_t *device_allocator,
      iree_host_size_t shape_rank, const iree_hal_dim_t *shape,
      iree_hal_element_type_t element_type, iree_hal_encoding_type_t encoding_type,
      iree_hal_buffer_params_t buffer_params, iree_const_byte_span_t initial_data,
      iree_hal_buffer_view_t **out_buffer_view);
  iree_host_size_t (*iree_hal_buffer_view_shape_rank)(const iree_hal_buffer_view_t *buffer_view);
  const iree_hal_dim_t *(*iree_hal_buffer_view_shape_dims)(const iree_hal_buffer_view_t *buffer_view);
  iree_hal_element_type_t (*iree_hal_buffer_view_element_type)(const iree_hal_buffer_view_t *buffer_view);
  iree_device_size_t (*iree_hal_buffer_view_byte_length)(const iree_hal_buffer_view_t *buffer_view);
  iree_hal_buffer_t *(*iree_hal_buffer_view_buffer)(const iree_hal_buffer_view_t *buffer_view);
  iree_status_t (*iree_hal_buffer_map_read)(iree_hal_buffer_t *buffer, iree_device_size_t source_offset,
                                            void *target_buffer, iree_device_size_t length);

  iree_vm_ref_t (*iree_hal_buffer_view_move_ref)(iree_hal_buffer_view_t *buffer_view);
  void (*iree_hal_device_release)(iree_hal_device_t *device);

  iree_status_t (*iree_hal_module_register_all_types)(iree_vm_instance_t *instance);
  iree_status_t (*iree_hal_module_resolve_all_types)(iree_vm_instance_t *instance);

  bool (*iree_status_to_string)(iree_status_t status, const iree_allocator_t *allocator,
                                char **out_buffer, iree_host_size_t *out_length);
  void (*iree_status_free)(iree_status_t status);
};

static struct runtime_symbols g_rt = {0};

static int load_symbol(void **fn_ptr, const char *name)
{
  *fn_ptr = dlsym(g_rt.handle, name);
  if (!*fn_ptr) {
    set_last_errorf("missing symbol: %s", name);
    return 0;
  }
  return 1;
}

static int ensure_runtime_loaded(const char *explicit_path)
{
  if (g_rt.handle) {
    return 1;
  }

  const char *env_path = getenv("X10_IREE_RUNTIME_LIB");
  const char *candidate_paths[] = {
      explicit_path,
      env_path,
      "libiree_runtime.dylib",
      "libiree_runtime.so",
      "iree_runtime.dll",
      NULL,
  };

  for (size_t i = 0; candidate_paths[i]; ++i) {
    const char *path = candidate_paths[i];
    if (!path || !*path) continue;
    g_rt.handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (g_rt.handle) {
      break;
    }
  }

  if (!g_rt.handle) {
    set_last_error("unable to load libiree_runtime (set X10_IREE_RUNTIME_LIB)");
    return 0;
  }

#define LOAD_SYM(name)                                                                             \
  do {                                                                                             \
    if (!load_symbol((void **)&g_rt.name, #name)) {                                                \
      dlclose(g_rt.handle);                                                                        \
      g_rt.handle = NULL;                                                                          \
      return 0;                                                                                    \
    }                                                                                              \
  } while (0)

  LOAD_SYM(iree_runtime_instance_options_initialize);
  LOAD_SYM(iree_runtime_instance_options_use_all_available_drivers);
  LOAD_SYM(iree_runtime_instance_create);
  LOAD_SYM(iree_runtime_instance_release);
  LOAD_SYM(iree_runtime_instance_host_allocator);
  LOAD_SYM(iree_runtime_instance_vm_instance);
  LOAD_SYM(iree_runtime_instance_try_create_default_device);
  LOAD_SYM(iree_runtime_session_options_initialize);
  LOAD_SYM(iree_runtime_session_create_with_device);
  LOAD_SYM(iree_runtime_session_release);
  LOAD_SYM(iree_runtime_session_device);
  LOAD_SYM(iree_runtime_session_device_allocator);
  LOAD_SYM(iree_runtime_session_append_bytecode_module_from_memory);
  LOAD_SYM(iree_runtime_session_call_by_name);
  LOAD_SYM(iree_vm_list_create);
  LOAD_SYM(iree_vm_list_release);
  LOAD_SYM(iree_vm_list_push_ref_move);
  LOAD_SYM(iree_vm_list_size);
  LOAD_SYM(iree_vm_list_get_buffer_view_assign);
  LOAD_SYM(iree_hal_buffer_view_allocate_buffer_copy);
  LOAD_SYM(iree_hal_buffer_view_shape_rank);
  LOAD_SYM(iree_hal_buffer_view_shape_dims);
  LOAD_SYM(iree_hal_buffer_view_element_type);
  LOAD_SYM(iree_hal_buffer_view_byte_length);
  LOAD_SYM(iree_hal_buffer_view_buffer);
  LOAD_SYM(iree_hal_buffer_map_read);
  LOAD_SYM(iree_hal_buffer_view_move_ref);
  LOAD_SYM(iree_hal_device_release);
  LOAD_SYM(iree_hal_module_register_all_types);
  LOAD_SYM(iree_hal_module_resolve_all_types);
  LOAD_SYM(iree_status_to_string);
  LOAD_SYM(iree_status_free);

#undef LOAD_SYM

  set_last_error(NULL);
  return 1;
}

int x10_iree_runtime_load(const char *explicit_path)
{
  return ensure_runtime_loaded(explicit_path);
}

void x10_iree_runtime_unload(void)
{
  if (g_rt.handle) {
    dlclose(g_rt.handle);
    memset(&g_rt, 0, sizeof(g_rt));
  }
}

int x10_iree_runtime_is_available(void)
{
  return 1;
}

// -----------------------------------------------------------------------------
// VM handle implementation
// -----------------------------------------------------------------------------

struct x10_iree_vm_s {
  iree_allocator_t host_allocator;
  iree_runtime_instance_t *instance;
  iree_hal_device_t *device;
  iree_runtime_session_t *session;
};

static void set_last_error_from_status(iree_status_t status)
{
  if (g_rt.iree_status_to_string && g_rt.iree_status_free) {
    iree_allocator_t allocator = x10_allocator_system();
    char *buffer = NULL;
    iree_host_size_t length = 0;
    if (g_rt.iree_status_to_string(status, &allocator, &buffer, &length)) {
      size_t copy = length;
      if (copy >= sizeof(g_last_error_buf)) copy = sizeof(g_last_error_buf) - 1;
      if (buffer) {
        memcpy(g_last_error_buf, buffer, copy);
        g_last_error_buf[copy] = '\0';
        free(buffer);
      }
    } else {
      set_last_error("IREE status error");
    }
    g_rt.iree_status_free(status);
  } else {
    set_last_error("IREE runtime error");
  }
}

static iree_hal_element_type_t map_dtype_to_element_type(x10_iree_dtype_t dtype)
{
  switch (dtype) {
    case X10_IREE_DTYPE_F16:  return IREE_HAL_ELEMENT_TYPE_FLOAT_16;
    case X10_IREE_DTYPE_BF16: return IREE_HAL_ELEMENT_TYPE_BFLOAT_16;
    case X10_IREE_DTYPE_F32:  return IREE_HAL_ELEMENT_TYPE_FLOAT_32;
    case X10_IREE_DTYPE_F64:  return IREE_HAL_ELEMENT_TYPE_FLOAT_64;
    case X10_IREE_DTYPE_I32:  return IREE_HAL_ELEMENT_TYPE_SINT_32;
    case X10_IREE_DTYPE_I64:  return IREE_HAL_ELEMENT_TYPE_SINT_64;
  }
  return IREE_HAL_ELEMENT_TYPE_NONE;
}

static int map_element_type_to_dtype(iree_hal_element_type_t element_type,
                                     x10_iree_dtype_t *out_dtype)
{
  switch (element_type) {
    case IREE_HAL_ELEMENT_TYPE_FLOAT_16:
      *out_dtype = X10_IREE_DTYPE_F16; return 1;
    case IREE_HAL_ELEMENT_TYPE_BFLOAT_16:
      *out_dtype = X10_IREE_DTYPE_BF16; return 1;
    case IREE_HAL_ELEMENT_TYPE_FLOAT_32:
      *out_dtype = X10_IREE_DTYPE_F32; return 1;
    case IREE_HAL_ELEMENT_TYPE_FLOAT_64:
      *out_dtype = X10_IREE_DTYPE_F64; return 1;
    case IREE_HAL_ELEMENT_TYPE_SINT_32:
      *out_dtype = X10_IREE_DTYPE_I32; return 1;
    case IREE_HAL_ELEMENT_TYPE_SINT_64:
      *out_dtype = X10_IREE_DTYPE_I64; return 1;
    default:
      break;
  }
  return 0;
}

static void release_vm(struct x10_iree_vm_s *vm)
{
  if (!vm) return;
  if (vm->session) {
    g_rt.iree_runtime_session_release(vm->session);
  }
  if (vm->device) {
    g_rt.iree_hal_device_release(vm->device);
  }
  if (vm->instance) {
    g_rt.iree_runtime_instance_release(vm->instance);
  }
  free(vm);
}

int x10_iree_vm_create_from_vmfb(const void *vmfb_data, size_t vmfb_size,
                                 x10_iree_vm_t **out_vm)
{
  if (!out_vm || !vmfb_data || vmfb_size == 0) {
    set_last_error("invalid arguments to vm_create_from_vmfb");
    return 0;
  }
  if (!ensure_runtime_loaded(NULL)) {
    return 0;
  }

  struct x10_iree_vm_s *vm = calloc(1, sizeof(*vm));
  if (!vm) {
    set_last_error("out of memory");
    return 0;
  }
  vm->host_allocator = x10_allocator_system();

  iree_runtime_instance_options_t instance_options;
  g_rt.iree_runtime_instance_options_initialize(&instance_options);
  g_rt.iree_runtime_instance_options_use_all_available_drivers(&instance_options);

  iree_status_t status = g_rt.iree_runtime_instance_create(&instance_options, vm->host_allocator, &vm->instance);
  if (!iree_status_is_ok(status)) {
    set_last_error_from_status(status);
    release_vm(vm);
    return 0;
  }

  iree_vm_instance_t *vm_instance = g_rt.iree_runtime_instance_vm_instance(vm->instance);
  if (vm_instance) {
    status = g_rt.iree_hal_module_register_all_types(vm_instance);
    if (!iree_status_is_ok(status)) {
      set_last_error_from_status(status);
      release_vm(vm);
      return 0;
    }
    status = g_rt.iree_hal_module_resolve_all_types(vm_instance);
    if (!iree_status_is_ok(status)) {
      set_last_error_from_status(status);
      release_vm(vm);
      return 0;
    }
  }

  const iree_string_view_t driver_names[] = {
      iree_make_cstring_view("local-task"),
      iree_make_cstring_view("local-sync"),
  };
  status = iree_ok_status();
  for (size_t i = 0; i < sizeof(driver_names) / sizeof(driver_names[0]); ++i) {
    status = g_rt.iree_runtime_instance_try_create_default_device(vm->instance, driver_names[i], &vm->device);
    if (iree_status_is_ok(status) && vm->device) {
      break;
    }
    if (!iree_status_is_ok(status)) {
      set_last_error_from_status(status);
    }
  }
  if (!vm->device) {
    release_vm(vm);
    return 0;
  }

  iree_runtime_session_options_t session_options;
  g_rt.iree_runtime_session_options_initialize(&session_options);
  status = g_rt.iree_runtime_session_create_with_device(
      vm->instance, &session_options, vm->device,
      g_rt.iree_runtime_instance_host_allocator(vm->instance), &vm->session);
  if (!iree_status_is_ok(status)) {
    set_last_error_from_status(status);
    release_vm(vm);
    return 0;
  }

  void *module_copy = malloc(vmfb_size);
  if (!module_copy) {
    set_last_error("out of memory (vmfb copy)");
    release_vm(vm);
    return 0;
  }
  memcpy(module_copy, vmfb_data, vmfb_size);
  iree_const_byte_span_t module_span = iree_make_const_byte_span(module_copy, vmfb_size);
  status = g_rt.iree_runtime_session_append_bytecode_module_from_memory(
      vm->session, module_span, vm->host_allocator);
  if (!iree_status_is_ok(status)) {
    set_last_error_from_status(status);
    release_vm(vm);
    return 0;
  }

  set_last_error(NULL);
  *out_vm = vm;
  return 1;
}

void x10_iree_vm_destroy(x10_iree_vm_t *vm)
{
  release_vm(vm);
}

static void free_results_internal(x10_iree_runtime_result_t *results, int32_t count)
{
  if (!results) return;
  for (int32_t i = 0; i < count; ++i) {
    free(results[i].shape);
    free(results[i].data);
  }
  free(results);
}

int x10_iree_vm_invoke(x10_iree_vm_t *vm, const char *entry_name,
                       const x10_iree_runtime_tensor_t *inputs, int32_t input_count,
                       x10_iree_runtime_result_t **out_results,
                       int32_t *out_result_count)
{
  if (!vm || !entry_name || !out_results || !out_result_count) {
    set_last_error("invalid arguments to vm_invoke");
    return 0;
  }

  iree_status_t status = iree_ok_status();
  iree_vm_list_t *input_list = NULL;
  iree_vm_list_t *output_list = NULL;

  status = g_rt.iree_vm_list_create(iree_vm_make_undefined_type_def(),
                                    (iree_host_size_t)input_count,
                                    vm->host_allocator, &input_list);
  if (!iree_status_is_ok(status)) {
    set_last_error_from_status(status);
    return 0;
  }

  status = g_rt.iree_vm_list_create(iree_vm_make_undefined_type_def(), 4,
                                    vm->host_allocator, &output_list);
  if (!iree_status_is_ok(status)) {
    set_last_error_from_status(status);
    g_rt.iree_vm_list_release(input_list);
    return 0;
  }

  for (int32_t i = 0; i < input_count; ++i) {
    const x10_iree_runtime_tensor_t *tensor = &inputs[i];
    if (!tensor->data && tensor->byte_length > 0) {
      set_last_error("input tensor missing data pointer");
      status = iree_status_from_code(IREE_STATUS_INVALID_ARGUMENT);
      break;
    }
    iree_hal_element_type_t element_type = map_dtype_to_element_type(tensor->dtype);
    if (element_type == IREE_HAL_ELEMENT_TYPE_NONE) {
      set_last_error("unsupported input dtype");
      status = iree_status_from_code(IREE_STATUS_INVALID_ARGUMENT);
      break;
    }

    const int32_t rank = tensor->rank;
    const int64_t *shape = tensor->shape;
    iree_hal_dim_t stack_shape[8];
    iree_hal_dim_t *dims = stack_shape;
    if (rank > (int32_t)(sizeof(stack_shape) / sizeof(stack_shape[0]))) {
      dims = malloc((size_t)rank * sizeof(iree_hal_dim_t));
      if (!dims) {
        set_last_error("out of memory (input dims)");
        status = iree_status_from_code(IREE_STATUS_RESOURCE_EXHAUSTED);
        break;
      }
    }
    for (int32_t d = 0; d < rank; ++d) {
      dims[d] = (iree_hal_dim_t)shape[d];
    }

    iree_hal_buffer_view_t *buffer_view = NULL;
    status = g_rt.iree_hal_buffer_view_allocate_buffer_copy(
        g_rt.iree_runtime_session_device(vm->session),
        g_rt.iree_runtime_session_device_allocator(vm->session),
        (iree_host_size_t)rank, dims, element_type,
        IREE_HAL_ENCODING_TYPE_DENSE_ROW_MAJOR,
        (iree_hal_buffer_params_t){
            .type = IREE_HAL_MEMORY_TYPE_DEVICE_LOCAL,
            .access = IREE_HAL_MEMORY_ACCESS_ALL,
            .usage = IREE_HAL_BUFFER_USAGE_DEFAULT,
        },
        iree_make_const_byte_span(tensor->data, tensor->byte_length),
        &buffer_view);

    if (dims != stack_shape) {
      free(dims);
    }

    if (!iree_status_is_ok(status)) {
      set_last_error_from_status(status);
      break;
    }

    iree_vm_ref_t buffer_ref = g_rt.iree_hal_buffer_view_move_ref(buffer_view);
    status = g_rt.iree_vm_list_push_ref_move(input_list, &buffer_ref);
    if (!iree_status_is_ok(status)) {
      set_last_error_from_status(status);
      break;
    }
  }

  if (iree_status_is_ok(status)) {
    status = g_rt.iree_runtime_session_call_by_name(
        vm->session, iree_make_cstring_view(entry_name), input_list, output_list);
    if (!iree_status_is_ok(status)) {
      set_last_error_from_status(status);
    }
  }

  if (!iree_status_is_ok(status)) {
    g_rt.iree_vm_list_release(input_list);
    g_rt.iree_vm_list_release(output_list);
    return 0;
  }

  iree_host_size_t result_count = g_rt.iree_vm_list_size(output_list);
  x10_iree_runtime_result_t *results = NULL;
  if (result_count > 0) {
    results = calloc(result_count, sizeof(*results));
    if (!results) {
      set_last_error("out of memory (results)");
      g_rt.iree_vm_list_release(input_list);
      g_rt.iree_vm_list_release(output_list);
      return 0;
    }
  }

  for (iree_host_size_t i = 0; i < result_count; ++i) {
    iree_hal_buffer_view_t *view = g_rt.iree_vm_list_get_buffer_view_assign(output_list, i);
    if (!view) {
      set_last_error("missing output buffer view");
      free_results_internal(results, (int32_t)result_count);
      g_rt.iree_vm_list_release(input_list);
      g_rt.iree_vm_list_release(output_list);
      return 0;
    }

    iree_host_size_t rank = g_rt.iree_hal_buffer_view_shape_rank(view);
    const iree_hal_dim_t *dims = g_rt.iree_hal_buffer_view_shape_dims(view);
    int64_t *shape = NULL;
    if (rank > 0) {
      shape = malloc(rank * sizeof(int64_t));
      if (!shape) {
        set_last_error("out of memory (result shape)");
        free_results_internal(results, (int32_t)result_count);
        g_rt.iree_vm_list_release(input_list);
        g_rt.iree_vm_list_release(output_list);
        return 0;
      }
      for (iree_host_size_t d = 0; d < rank; ++d) {
        shape[d] = (int64_t)dims[d];
      }
    }

    x10_iree_dtype_t dtype;
    if (!map_element_type_to_dtype(g_rt.iree_hal_buffer_view_element_type(view), &dtype)) {
      set_last_error("unsupported output dtype");
      free(shape);
      free_results_internal(results, (int32_t)result_count);
      g_rt.iree_vm_list_release(input_list);
      g_rt.iree_vm_list_release(output_list);
      return 0;
    }

    iree_device_size_t byte_length = g_rt.iree_hal_buffer_view_byte_length(view);
    void *data = NULL;
    if (byte_length > 0) {
      data = malloc((size_t)byte_length);
      if (!data) {
        set_last_error("out of memory (result data)");
        free(shape);
        free_results_internal(results, (int32_t)result_count);
        g_rt.iree_vm_list_release(input_list);
        g_rt.iree_vm_list_release(output_list);
        return 0;
      }
      status = g_rt.iree_hal_buffer_map_read(
          g_rt.iree_hal_buffer_view_buffer(view), 0, data, byte_length);
      if (!iree_status_is_ok(status)) {
        set_last_error_from_status(status);
        free(shape);
        free_results_internal(results, (int32_t)result_count);
        g_rt.iree_vm_list_release(input_list);
        g_rt.iree_vm_list_release(output_list);
        return 0;
      }
    }

    results[i].dtype = dtype;
    results[i].rank = (int32_t)rank;
    results[i].shape = shape;
    results[i].data = data;
    results[i].byte_length = (size_t)byte_length;
  }

  g_rt.iree_vm_list_release(input_list);
  g_rt.iree_vm_list_release(output_list);

  *out_results = results;
  *out_result_count = (int32_t)result_count;
  set_last_error(NULL);
  return 1;
}

void x10_iree_runtime_free_results(x10_iree_runtime_result_t *results,
                                   int32_t result_count)
{
  free_results_internal(results, result_count);
}

#else  // !X10_IREE_HAVE_HEADERS

static const char *g_last_error = "compiled without IREE headers";

const char *x10_iree_runtime_last_error(void) { return g_last_error; }
int x10_iree_runtime_is_available(void) { return 0; }
int x10_iree_runtime_load(const char *explicit_path) {
  (void)explicit_path;
  return 0;
}
void x10_iree_runtime_unload(void) {}
int x10_iree_vm_create_from_vmfb(const void *vmfb_data, size_t vmfb_size,
                                 x10_iree_vm_t **out_vm) {
  (void)vmfb_data;
  (void)vmfb_size;
  (void)out_vm;
  return 0;
}
void x10_iree_vm_destroy(x10_iree_vm_t *vm) { (void)vm; }
int x10_iree_vm_invoke(x10_iree_vm_t *vm, const char *entry_name,
                       const x10_iree_runtime_tensor_t *inputs, int32_t input_count,
                       x10_iree_runtime_result_t **out_results,
                       int32_t *out_result_count) {
  (void)vm;
  (void)entry_name;
  (void)inputs;
  (void)input_count;
  (void)out_results;
  (void)out_result_count;
  return 0;
}
void x10_iree_runtime_free_results(x10_iree_runtime_result_t *results,
                                   int32_t result_count) {
  (void)results;
  (void)result_count;
}

#endif  // X10_IREE_HAVE_HEADERS
