// Windows monotonic clock bridge; no prime-calculation logic.
#include <windows.h>
static double now_ns(void) { LARGE_INTEGER value, frequency; QueryPerformanceCounter(&value); QueryPerformanceFrequency(&frequency); return (double)value.QuadPart * (1000000000.0 / (double)frequency.QuadPart); }
__declspec(dllexport) void primesieve_clock(double *out) { *out=now_ns(); }
__declspec(dllexport) double primesieve_now(void) { return now_ns(); }
#ifdef LUA_CLOCK
// Resolve the functions from the interpreter already loaded in this process.
#include <psapi.h>
struct lua_State;
typedef void (__cdecl *push_number)(struct lua_State*,double);
typedef void (__cdecl *push_closure)(struct lua_State*,int(*)(struct lua_State*),int);
static push_number number;
static int tick(struct lua_State *L) { number(L,now_ns()); return 1; }
__declspec(dllexport) int luaopen_primesieve_clock(struct lua_State *L) {
 HMODULE modules[1024]; DWORD bytes=0; push_closure closure=0;
 if(!EnumProcessModules(GetCurrentProcess(),modules,sizeof(modules),&bytes)) return 0;
 for(unsigned i=0;i<bytes/sizeof(HMODULE) && i<1024;i++) {
  number=(push_number)GetProcAddress(modules[i],"lua_pushnumber");
  closure=(push_closure)GetProcAddress(modules[i],"lua_pushcclosure");
  if(number && closure) { closure(L,tick,0); return 1; }
 }
 return 0;
}
#endif
