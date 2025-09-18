#include "x10_pjrt_shim.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h> // strcasecmp on POSIX

#ifdef X10_PJRT_DLOPEN
#include <dlfcn.h>
#endif

// If real headers are present, we can hold a typed API table; otherwise we just
// check symbol presence and run in stub mode when needed.
#if defined(X10_PJRT_HAVE_HEADERS)
// x10_pjrt_c_api_inc.h included from the header may pull pjrt_c_api.h
static const PJRT_Api *s_api = NULL;
typedef const PJRT_Api *(*pjrt_api_fn_t)(void);
#else
typedef void *(*pjrt_api_fn_t)(void);
#endif

// ---------- Small helpers ----------

static int getenv_int(const char *key, int fallback)
{
  const char *v = getenv(key);
  if (!v || !*v)
    return fallback;
  char *end = NULL;
  long n = strtol(v, &end, 10);
  if (end == v)
    return fallback;
  if (n < 0)
    n = 0;
  return (int)n;
}

static int getenv_bool(const char *key)
{
  const char *v = getenv(key);
  if (!v)
    return 0;
  if (!*v)
    return 0;
  // false iff { "0", "false", "no", "off" } (case-insensitive)
  if (!strcasecmp(v, "0"))
    return 0;
  if (!strcasecmp(v, "false"))
    return 0;
  if (!strcasecmp(v, "no"))
    return 0;
  if (!strcasecmp(v, "off"))
    return 0;
  return 1;
}

// Safe copy with truncation; always NUL-terminates when capacity > 0.
static void copy_trunc(char *dst, size_t cap, const char *src)
{
  if (cap == 0)
    return;
  size_t n = strlen(src ? src : "");
  if (n >= cap)
    n = cap - 1;
  memcpy(dst, src ? src : "", n);
  dst[n] = '\0';
}

// ---------- Loader state & last-error ----------

static int s_loaded = -1; // -1 unknown, 0 not loaded, 1 loaded (real PJRT present)
#ifdef X10_PJRT_DLOPEN
static void *s_handle = NULL;
#endif

static const char *s_last_err = "";
static void set_last_error(const char *msg)
{
  static char buf[256];
  copy_trunc(buf, sizeof(buf), msg ? msg : "");
  s_last_err = buf;
}

int x10_pjrt_load(const char *explicit_path)
{
  if (s_loaded == 1)
    return 1;
  if (getenv_bool("X10_PJRT_FORCE_STUB"))
  {
    s_loaded = 0;
    set_last_error("forced stub");
    return 0;
  }

#ifdef X10_PJRT_DLOPEN
  const char *env_path = getenv("X10_PJRT_LIB");
  const char *path = (explicit_path && *explicit_path) ? explicit_path : env_path;

  const char *candidates[10] = {0};
  int idx = 0;
  if (path)
    candidates[idx++] = path;

#if defined(__APPLE__)
  candidates[idx++] = "libpjrt_c.dylib";
  candidates[idx++] = "/opt/homebrew/lib/libpjrt_c.dylylb"; // optional; adjust as needed
  candidates[idx++] = "/usr/local/lib/libpjrt_c.dylib";
#else
  candidates[idx++] = "libpjrt_c.so";
  candidates[idx++] = "/usr/local/lib/libpjrt_c.so";
  candidates[idx++] = "/usr/lib/libpjrt_c.so";
  candidates[idx++] = "/lib/libpjrt_c.so";
#endif
  candidates[idx] = NULL;

  for (int i = 0; candidates[i]; ++i)
  {
    s_handle = dlopen(candidates[i], RTLD_LAZY | RTLD_LOCAL);
    if (!s_handle)
      continue;

    pjrt_api_fn_t sym = (pjrt_api_fn_t)dlsym(s_handle, "PJRT_Api");
    if (sym)
    {
#if defined(X10_PJRT_HAVE_HEADERS)
      const PJRT_Api *api = sym();
      if (api)
      {
        s_loaded = 1;
        s_last_err = "";
        s_api = api;
        return 1;
      }
#else
      s_loaded = 1;
      s_last_err = "";
      return 1;
#endif
    }
    dlclose(s_handle);
    s_handle = NULL;
  }

  s_loaded = 0;
  set_last_error("PJRT library not found (set X10_PJRT_LIB or install libpjrt_c)");
  return 0;
#else
  s_loaded = 0;
  set_last_error("PJRT loader built without dlopen support");
  return 0;
#endif
}

void x10_pjrt_unload(void)
{
#ifdef X10_PJRT_DLOPEN
  if (s_handle)
  {
    dlclose(s_handle);
    s_handle = NULL;
  }
#endif
#if defined(X10_PJRT_HAVE_HEADERS)
  s_api = NULL;
#endif
  s_loaded = 0;
  set_last_error("");
}

const char *x10_pjrt_last_error(void)
{
  return s_last_err ? s_last_err : "";
}

int x10_pjrt_is_available(void)
{
  if (s_loaded == -1)
    (void)x10_pjrt_load(NULL);
  // Available if real PJRT loaded or we can stub (always true here).
  return (s_loaded == 1) || 1;
}

// ---------- Stubbed device enumeration (no client) ----------

int32_t x10_pjrt_device_count(void)
{
  int n = getenv_int("X10_PJRT_STUB_DEVICE_COUNT", 1);
  if (n < 0)
    n = 0;
  return (int32_t)n;
}

size_t x10_pjrt_device_description(int32_t index, char *buffer, size_t capacity)
{
  char tmp[64];
  snprintf(tmp, sizeof(tmp), "gpu:%d (stub%s)", (int)index, (s_loaded == 1 ? "+pjrt" : ""));
  size_t need = strlen(tmp);
  if (capacity > 0 && buffer)
    copy_trunc(buffer, capacity, tmp);
  return need;
}

// ---------- Client API (stub now; real path when headers present) ----------

// Opaque body (private to C side)
struct x10_pjrt_client
{
  int stub;
};

int x10_pjrt_client_create(x10_pjrt_client_t *out_client)
{
  if (!out_client)
  {
    set_last_error("null out_client");
    return 0;
  }

#if defined(X10_PJRT_HAVE_HEADERS)
  if (s_loaded != 1)
    (void)x10_pjrt_load(NULL);
  if (s_loaded == 1 && s_api)
  {
    // TODO: wire PJRT_Client_Create once headers are vendored.
    // For now fall through to stub.
  }
#endif

  // Allocate the underlying struct and return a typed pointer.
  x10_pjrt_client_t c = (x10_pjrt_client_t)malloc(sizeof(struct x10_pjrt_client));
  if (!c)
  {
    set_last_error("malloc failed");
    return 0;
  }
  c->stub = 1;
  *out_client = c;
  return 1;
}

void x10_pjrt_client_destroy(x10_pjrt_client_t client)
{
  if (!client)
    return;
#if defined(X10_PJRT_HAVE_HEADERS)
  if (s_loaded == 1 && s_api)
  {
    // TODO: PJRT_Client_Destroy when real client is used.
  }
#endif
  free(client);
}

int x10_pjrt_client_device_count(x10_pjrt_client_t client, int32_t *out_count)
{
  if (!client || !out_count)
  {
    set_last_error("null arg");
    return 0;
  }

#if defined(X10_PJRT_HAVE_HEADERS)
  if (s_loaded == 1 && s_api)
  {
    // TODO: query real devices; fall through to stub for now.
  }
#endif

  *out_count = x10_pjrt_device_count();
  return 1;
}

// ... keep your existing includes, helpers, loader and client code ...

// ---------- Executable (stub now; real path when headers present) ----------

struct x10_pjrt_executable
{
  int stub;
  int id;
};
static int s_next_exec_id = 1;

int x10_pjrt_compile_stablehlo(x10_pjrt_client_t client,
                               const char *stablehlo_text,
                               size_t text_len,
                               const char *options_json,
                               x10_pjrt_executable_t *out_exec)
{
  if (!client || !out_exec || !stablehlo_text)
  {
    set_last_error("null arg");
    return 0;
  }

#if defined(X10_PJRT_HAVE_HEADERS)
  if (s_loaded != 1)
    (void)x10_pjrt_load(NULL);
  if (s_loaded == 1 && s_api)
  {
    // TODO: call real PJRT compile here (guarded)
    // For now, fall through to stub so code runs everywhere.
  }
#endif

  x10_pjrt_executable_t e = (x10_pjrt_executable_t)malloc(sizeof(struct x10_pjrt_executable));
  if (!e)
  {
    set_last_error("malloc failed");
    return 0;
  }
  e->stub = 1;
  e->id = s_next_exec_id++;
  *out_exec = e;
  return 1;
}

void x10_pjrt_executable_destroy(x10_pjrt_executable_t exec)
{
  if (!exec)
    return;
#if defined(X10_PJRT_HAVE_HEADERS)
  if (s_loaded == 1 && s_api)
  {
    // TODO: destroy real PJRT executable when used.
  }
#endif
  free(exec);
}

int x10_pjrt_execute(x10_pjrt_executable_t exec, int32_t device_ordinal)
{
  if (!exec)
  {
    set_last_error("null exec");
    return 0;
  }
#if defined(X10_PJRT_HAVE_HEADERS)
  if (s_loaded == 1 && s_api)
  {
    // TODO: real enqueue/execute via PJRT (streams/events later).
    // For now, fall through to stub.
  }
#endif
  (void)device_ordinal;
  return 1; // stub success
}

int x10_pjrt_is_real(void)
{
#if defined(X10_PJRT_HAVE_HEADERS)
  if (s_loaded == -1)
    (void)x10_pjrt_load(NULL);
#if defined(X10_PJRT_HAVE_HEADERS)
  return (s_loaded == 1
#if defined(X10_PJRT_HAVE_HEADERS)
          && s_api != NULL
#endif
          )
             ? 1
             : 0;
#else
  return 0;
#endif
#else
  (void)s_loaded;
  return 0;
#endif
}
