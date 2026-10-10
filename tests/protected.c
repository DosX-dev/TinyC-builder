#define VIRT 1
#define CFLOW_V2 1
#include <stdio.h>
#include <obfus.h>

static int transform(int value) {
    if (value > 0) return value * 3;
    else return value - 2;
}

int main(void) {
    int sum = 0, calls = 0;
    for (int n = -8; n <= 8; ++n) {
        sum += transform(n);
        if (++calls != n + 9) return 1;
    }
    if (sum != 54 || calls != 17) return 2;
    puts("OBFUS_HEADER_PASS");
    return 0;
}
