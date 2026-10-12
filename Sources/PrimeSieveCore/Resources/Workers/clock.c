// Monotonic clock bridge for worker timing; contains no prime-calculation logic.
#include <time.h>
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (double)t.tv_sec*1e9+t.tv_nsec;}
void primesieve_clock(double*out){*out=now();}
double primesieve_now(void){return now();}
#ifdef LUA_CLOCK
struct lua_State;extern void lua_pushnumber(struct lua_State*,double);extern void lua_pushcclosure(struct lua_State*,int(*)(struct lua_State*),int);
static int tick(struct lua_State*L){lua_pushnumber(L,now());return 1;}
int luaopen_primesieve_clock(struct lua_State*L){lua_pushcclosure(L,tick,0);return 1;}
#endif
