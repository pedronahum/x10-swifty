#ifndef X10_PJRT_C_API_INC_H
#define X10_PJRT_C_API_INC_H

// If you vendor pjrt_c_api.h into the repo, define X10_PJRT_HAVE_HEADERS
// in PJRTC.cSettings (Package.swift) or via build settings, and include it here.
#if defined(X10_PJRT_HAVE_HEADERS)
// Option A: vendored header
#include "third_party/pjrt/pjrt_c_api.h"
// Option B: system header on your include path
// #include <pjrt_c_api.h>
#endif

#endif // X10_PJRT_C_API_INC_H
