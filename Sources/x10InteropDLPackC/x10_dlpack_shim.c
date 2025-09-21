#include "x10_dlpack_shim.h"
#include <stdlib.h>
#include <string.h>

#include <dlpack/dlpack.h>

struct x10_dl_capsule
{
  DLManagedTensor *mt;
  int64_t *shape_copy;
  int64_t *strides_copy;
  int refcount;
  int32_t device_type;
  int32_t device_id;
};

static const char *g_last_error = "";
static void set_last_error(const char *msg) { g_last_error = msg ? msg : ""; }

int x10_dlpack_is_available(void) { return 1; }
const char *x10_dlpack_last_error(void) { return g_last_error; }

// --- deleters ---

static void x10_dl_deleter_free_data(DLManagedTensor *self)
{
  if (!self)
    return;
  if (self->dl_tensor.data)
    free(self->dl_tensor.data);
  // DLManagedTensor freed by capsule dispose
}

// --- internal helpers ---

static x10_dl_capsule_t x10_alloc_capsule(
    void *data,
    const int64_t *shape, int32_t ndim,
    DLDataType dtype,
    DLDevice device,
    DLManagedTensor **out_mt /*optional*/,
    void (*deleter)(DLManagedTensor *))
{
  set_last_error("");
  if (!data || !shape || ndim <= 0)
  {
    set_last_error("invalid args");
    return NULL;
  }

  x10_dl_capsule_t cap = (x10_dl_capsule_t)calloc(1, sizeof(*cap));
  if (!cap)
  {
    set_last_error("oom");
    return NULL;
  }

  cap->mt = (DLManagedTensor *)calloc(1, sizeof(DLManagedTensor));
  if (!cap->mt)
  {
    free(cap);
    set_last_error("oom");
    return NULL;
  }

  cap->shape_copy = (int64_t *)malloc(sizeof(int64_t) * (size_t)ndim);
  if (!cap->shape_copy)
  {
    free(cap->mt);
    free(cap);
    set_last_error("oom");
    return NULL;
  }
  memcpy(cap->shape_copy, shape, sizeof(int64_t) * (size_t)ndim);

  cap->strides_copy = NULL; // dense
  cap->refcount = 1;
  cap->device_type = (int32_t)device.device_type;
  cap->device_id = (int32_t)device.device_id;

  DLTensor *t = &cap->mt->dl_tensor;
  t->data = data;
  t->device = device;
  t->ndim = ndim;
  t->dtype = dtype;
  t->shape = cap->shape_copy;
  t->strides = NULL;
  t->byte_offset = 0;

  cap->mt->manager_ctx = NULL;
  cap->mt->deleter = deleter;

  if (out_mt)
    *out_mt = cap->mt;
  return cap;
}

// --- API impl ---

x10_dl_capsule_t x10_dlpack_wrap_host_buffer_free(
    void *data,
    const int64_t *shape, int32_t ndim,
    int32_t dtype_code, int32_t dtype_bits, int32_t dtype_lanes)
{
  DLDevice dev = {.device_type = kDLCPU, .device_id = 0};
  DLDataType dt = {.code = (uint8_t)dtype_code, .bits = (uint8_t)dtype_bits, .lanes = (uint16_t)dtype_lanes};
  return x10_alloc_capsule(data, shape, ndim, dt, dev, NULL, x10_dl_deleter_free_data);
}

int x10_dlpack_wrap_host_copy(
    const void *bytes, size_t nbytes,
    const int64_t *shape, int32_t ndim,
    int32_t dtype_code, int32_t dtype_bits, int32_t dtype_lanes,
    int32_t device_type, int32_t device_id,
    x10_dl_capsule_t *out_cap)
{
  set_last_error("");
  if (!bytes || !shape || ndim <= 0 || !out_cap)
  {
    set_last_error("invalid args");
    return 0;
  }
  void *data = malloc(nbytes);
  if (!data)
  {
    set_last_error("oom");
    return 0;
  }
  memcpy(data, bytes, nbytes);

  DLDevice dev = {.device_type = (DLDeviceType)device_type, .device_id = device_id};
  DLDataType dt = {.code = (uint8_t)dtype_code, .bits = (uint8_t)dtype_bits, .lanes = (uint16_t)dtype_lanes};
  x10_dl_capsule_t cap = x10_alloc_capsule(data, shape, ndim, dt, dev, NULL, x10_dl_deleter_free_data);
  if (!cap)
  {
    free(data);
    return 0;
  }
  *out_cap = cap;
  return 1;
}

x10_dl_capsule_t x10_dlpack_retain(x10_dl_capsule_t cap)
{
  if (cap)
    cap->refcount++;
  return cap;
}

void x10_dlpack_dispose(x10_dl_capsule_t cap)
{
  if (!cap)
    return;
  if (--cap->refcount > 0)
    return;
  if (cap->mt && cap->mt->deleter)
  {
    cap->mt->deleter(cap->mt); // free data if owner
  }
  if (cap->shape_copy)
    free(cap->shape_copy);
  if (cap->strides_copy)
    free(cap->strides_copy);
  if (cap->mt)
    free(cap->mt);
  free(cap);
}

int x10_dlpack_basic_info(
    x10_dl_capsule_t cap,
    int32_t *out_device_type, int32_t *out_device_id,
    int32_t *out_dtype_code, int32_t *out_dtype_bits, int32_t *out_dtype_lanes,
    int32_t *out_ndim)
{
  set_last_error("");
  if (!cap || !cap->mt)
  {
    set_last_error("null cap");
    return 0;
  }
  const DLTensor *t = &cap->mt->dl_tensor;
  if (out_device_type)
    *out_device_type = (int32_t)t->device.device_type;
  if (out_device_id)
    *out_device_id = (int32_t)t->device.device_id;
  if (out_dtype_code)
    *out_dtype_code = (int32_t)t->dtype.code;
  if (out_dtype_bits)
    *out_dtype_bits = (int32_t)t->dtype.bits;
  if (out_dtype_lanes)
    *out_dtype_lanes = (int32_t)t->dtype.lanes;
  if (out_ndim)
    *out_ndim = (int32_t)t->ndim;
  return 1;
}

int x10_dlpack_shape(x10_dl_capsule_t cap, int64_t *out_shape, int32_t capacity)
{
  set_last_error("");
  if (!cap || !cap->mt)
  {
    set_last_error("null cap");
    return -1;
  }
  const DLTensor *t = &cap->mt->dl_tensor;
  if (!out_shape || capacity < (int32_t)t->ndim)
  {
    set_last_error("capacity too small");
    return -1;
  }
  for (int i = 0; i < (int)t->ndim; ++i)
    out_shape[i] = t->shape[i];
  return (int)t->ndim;
}

int x10_dlpack_data_ptr(x10_dl_capsule_t cap, void **out_ptr, size_t *out_byte_offset)
{
  set_last_error("");
  if (!cap || !cap->mt || !out_ptr)
  {
    set_last_error("null arg");
    return 0;
  }
  const DLTensor *t = &cap->mt->dl_tensor;
  *out_ptr = (void *)((char *)t->data + t->byte_offset);
  if (out_byte_offset)
    *out_byte_offset = (size_t)t->byte_offset;
  return 1;
}

// Optional utility used by Swift for copying out
static size_t x10_dlpack_nbytes(const DLTensor *t)
{
  if (!t || t->ndim <= 0)
    return 0;
  size_t elems = 1;
  for (int i = 0; i < t->ndim; ++i)
    elems *= (size_t)t->shape[i];
  size_t bytes_per_lane = (size_t)(t->dtype.bits / 8u);
  size_t lanes = (size_t)(t->dtype.lanes ? t->dtype.lanes : 1);
  return elems * bytes_per_lane * lanes;
}

int x10_dlpack_to_host_copy(
    x10_dl_capsule_t cap,
    void *out, size_t out_capacity,
    int *out_written)
{
  set_last_error("");
  if (!cap || !cap->mt)
  {
    set_last_error("null cap");
    return 0;
  }
  const DLTensor *t = &cap->mt->dl_tensor;
  size_t need = x10_dlpack_nbytes(t);
  if (out_written)
    *out_written = (int)need;
  if (!out || out_capacity == 0)
    return 1; // probe mode
  if (out_capacity < need)
  {
    set_last_error("buffer too small");
    return 0;
  }
  memcpy(out, (const char *)t->data + t->byte_offset, need);
  return 1;
}
