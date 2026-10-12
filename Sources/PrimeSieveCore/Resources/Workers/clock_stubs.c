// Monotonic clock bridge for worker timing; contains no prime-calculation logic.
#include <time.h>
#include <caml/mlvalues.h>
#include <caml/alloc.h>
CAMLprim value primesieve_monotonic(value unit){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return caml_copy_double((double)t.tv_sec*1e9+t.tv_nsec);}
