#include "x10_dlpack_shim.h"
#include <stdlib.h>
#include <string.h>

static const char *g_last_error = "";
static void set_last_error(const char *msg) { g_last_error = msg ? msg : ""; }

const char *x10_dlpack_last_error(void) { return g_last_error; }

int x10_dlpack_is_available(void)
{
#if defined(X10_HAVE_DLPACK_HEADERS)
  return 1;
#else
  return 0;
#endif
}

int x10_dlpack_dispose(x10_dl_capsule_t cap)
{
#if defined(X10_HAVE_DLPACK_HEADERS)
  if (!cap)
    return 1;
  typedef struct DLManagedTensor DLManagedTensor;
  extern void x10_dlpack_internal_call_deleter(void *mt);
  x10_dlpack_internal_call_deleter(cap->_opaque);
  free(cap);
  return 1;
#else
  (void)cap;
  return 1;
#endif
}

#if defined(X10_HAVE_DLPACK_HEADERS)

// ----------------------- REAL PATH (headers present) -------------------------
#include <dlpack/dlpack.h>

typedef struct
{
  void *data;
  size_t nbytes;
  int64_t *shape;
  int ndim;
} x10_owned_host_t;

static void x10_host_deleter(DLManagedTensor *self)
{
  if (!self)
    return;
  x10_owned_host_t *st = (x10_owned_host_t *)self->manager_ctx;
  if (st)
  {
    if (st->data)
      free(st->data);
    if (st->shape)
      free(st->shape);
    free(st);
  }
  free(self);
}

static size_t x10_elem_size(int32_t bits, int32_t lanes)
{
  if (lanes <= 0)
    return 0;
  if (bits % 8 != 0)
    return 0;
  return (size_t)(bits / 8) * (size_t)lanes;
}

static size_t x10_total_nbytes(const DLTensor *t)
{
  size_t el = x10_elem_size(t->dtype.bits, t->dtype.lanes);
  if (el == 0)
    return 0;
  size_t elems = 1;
  for (int i = 0; i < t->ndim; ++i)
    elems *= (size_t)t->shape[i];
  return el * elems;
}

int x10_dlpack_wrap_host_copy(
    const void *data, size_t nbytes,
    const int64_t *shape, int ndim,
    int32_t code, int32_t bits, int32_t lanes,
    int32_t device_type, int32_t device_id,
    x10_dl_capsule_t *out_cap)
{
  if (!data || !shape || ndim <= 0 || !out_cap)
  {
    set_last_error("bad args");
    return 0;
  }
  size_t el = x10_elem_size(bits, lanes);
  if (el == 0)
  {
    set_last_error("unsupported dtype");
    return 0;
  }

  // Allocate owned copies
  void *buf = malloc(nbytes);
  if (!buf)
  {
    set_last_error("malloc data failed");
    return 0;
  }
  memcpy(buf, data, nbytes);

  int64_t *shp = (int64_t *)malloc((size_t)ndim * sizeof(int64_t));
  if (!shp)
  {
    free(buf);
    set_last_error("malloc shape failed");
    return 0;
  }
  memcpy(shp, shape, (size_t)ndim * sizeof(int64_t));

  x10_owned_host_t *st = (x10_owned_host_t *)malloc(sizeof(x10_owned_host_t));
  if (!st)
  {
    free(buf);
    free(shp);
    set_last_error("malloc state failed");
    return 0;
  }
  st->data = buf;
  st->nbytes = nbytes;
  st->shape = shp;
  st->ndim = ndim;

  DLManagedTensor *mt = (DLManagedTensor *)malloc(sizeof(DLManagedTensor));
  if (!mt)
  {
    free(buf);
    free(shp);
    free(st);
    set_last_error("malloc mt failed");
    return 0;
  }
  memset(mt, 0, sizeof(*mt));

  mt->dl_tensor.data = buf;
  mt->dl_tensor.device.device_type = (DLDeviceType)device_type;
  mt->dl_tensor.device.device_id = device_id;
  mt->dl_tensor.ndim = ndim;
  mt->dl_tensor.dtype.code = (uint8_t)code;
  mt->dl_tensor.dtype.bits = (uint8_t)bits;
  mt->dl_tensor.dtype.lanes = (uint16_t)lanes;
  mt->dl_tensor.shape = shp;
  mt->dl_tensor.strides = NULL;
  mt->dl_tensor.byte_offset = 0;

  mt->manager_ctx = st;
  mt->deleter = x10_host_deleter;

  x10_dl_capsule_t cap = (x10_dl_capsule_t)malloc(sizeof(*cap));
  if (!cap)
  {
    x10_host_deleter(mt);
    set_last_error("malloc cap failed");
    return 0;
  }
  cap->_opaque = (void *)mt;
  *out_cap = cap;
  return 1;
}

int x10_dlpack_to_host_copy(
    x10_dl_capsule_t cap, void *dst, size_t dst_size, size_t *written)
{
  if (!cap || !cap->_opaque)
  {
    set_last_error("null cap");
    return 0;
  }
  DLManagedTensor *mt = (DLManagedTensor *)cap->_opaque;
  size_t need = x10_total_nbytes(&mt->dl_tensor);
  if (written)
    *written = need;
  if (!dst)
    return 1;
  if (dst_size < need)
  {
    set_last_error("dst too small");
    return 0;
  }
  memcpy(dst, mt->dl_tensor.data, need);
  return 1;
}

// Helper so dispose() can call deleter
void x10_dlpack_internal_call_deleter(void *mt_raw)
{
  DLManagedTensor *mt = (DLManagedTensor *)mt_raw;
  if (mt && mt->deleter)
    mt->deleter(mt);
}

#else // --------------------- STUB PATH (no headers) -------------------------

int x10_dlpack_wrap_host_copy(
    const void *data, size_t nbytes,
    const int64_t *shape, int ndim,
    int32_t code, int32_t bits, int32_t lanes,
    int32_t device_type, int32_t device_id,
    x10_dl_capsule_t *out_cap)
{
  (void)data;
  (void)nbytes;
  (void)shape;
  (void)ndim;
  (void)code;
  (void)bits;
  (void)lanes;
  (void)device_type;
  (void)device_id;
  (void)out_cap;
  set_last_error("compiled without DLPack headers");
  return 0;
}

int x10_dlpack_to_host_copy(
    x10_dl_capsule_t cap, void *dst, size_t dst_size, size_t *written)
{
  (void)cap;
  (void)dst;
  (void)dst_size;
  if (written)
    *written = 0;
  set_last_error("compiled without DLPack headers");
  return 0;
}

#endif
