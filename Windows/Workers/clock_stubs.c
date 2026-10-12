#include <windows.h>
static double now_ns(void) { LARGE_INTEGER value, frequency; QueryPerformanceCounter(&value); QueryPerformanceFrequency(&frequency); return (double)value.QuadPart * (1000000000.0 / (double)frequency.QuadPart); }
#include <caml/mlvalues.h>
#include <caml/alloc.h>
CAMLprim value primesieve_monotonic(value unit) { return caml_copy_double(now_ns()); }
