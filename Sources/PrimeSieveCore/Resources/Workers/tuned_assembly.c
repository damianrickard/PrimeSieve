// Protocol 3. Assembly owns marking/scanning; C owns timing and allocation.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
static double now_ns(void) { LARGE_INTEGER t,f; QueryPerformanceCounter(&t); QueryPerformanceFrequency(&f); return (double)t.QuadPart*1e9/f.QuadPart; }
#else
#include <time.h>
static double now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return (double)t.tv_sec*1e9+t.tv_nsec; }
#endif
extern uint64_t tuned_kernel(unsigned char *, uint64_t, uint64_t);
extern uint64_t tuned_scan(unsigned char *, uint64_t, uint64_t);
static volatile unsigned char observed;
int main(int argc,char **argv) {
    if(argc!=10) return 2;
    uint64_t n=strtoull(argv[1],0,10), limit=strtoull(argv[2],0,10);
    int warm=atoi(argv[3]), runs=atoi(argv[4]), throughput=!strcmp(argv[5],"throughput"), full=!strcmp(argv[9],"1");
    double duration=strtod(argv[6],0)*1e9;
    size_t size=limit/2+1;
    for(int run=-warm;run<runs;run++) {
        unsigned char *flags=NULL;
        uint64_t passes=0,last=0;
        double elapsed,start=now_ns();
        do {
            unsigned char *next=calloc(size,1); if(!next){free(flags);return 3;}
            last=tuned_kernel(next,limit,throughput ? 0 : n);
            if(throughput)observed^=next[passes%size];
            free(flags);flags=next;
            ++passes;elapsed=now_ns()-start;
        } while(run>=0 && throughput && elapsed<duration);
        if(run<0){free(flags);continue;}
        if(throughput)last=tuned_scan(flags,limit,n);
        uint64_t sum=2;
        for(uint64_t p=3;p<=last;p+=2)if(!flags[p/2])sum=(sum+p)%1000000007;
        printf("{\"elapsed_ns\":%.0f,\"passes\":%llu,\"count\":%llu,\"last_prime\":%llu,\"checksum\":%llu,\"observation\":%u",elapsed,(unsigned long long)passes,(unsigned long long)(last?n:0),(unsigned long long)last,(unsigned long long)sum,observed);
        if(full){printf(",\"primes\":[2");for(uint64_t p=3;p<=last;p+=2)if(!flags[p/2])printf(",%llu",(unsigned long long)p);printf("]");}
        printf("}\n");fflush(stdout);free(flags);
    }
}
