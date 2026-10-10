#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

#define VIRT 1
#define CFLOW_V2 1
#define FAKE_SIGNS 1
#define ANTIDEBUG_V2 1
#include "obfus.h"

static int transform(int value) {
    if (value > 0)
        return value * 3;
    else
        return value - 2;
}

static int fibonacci(int n) {
    if (n < 2) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

static DWORD WINAPI worker(void *argument) {
    int *result = argument;
    *result = fibonacci(8);
    return 0;
}

__declspec(dllexport) int obfh_bundle_check(int input) {
    int sum = 0, calls = 0;
    for (int n = -8; n <= 8; ++n) {
        sum += transform(n);
        if (++calls != n + 9) return 1;
    }
    if (sum != 54 || calls != 17) return 2;

    int side_effect = 0;
    if (input && ++side_effect) sum += 1;
    if (!input && ++side_effect) sum += 2;
    if (side_effect != 1 || sum != (input ? 55 : 56)) return 3;

    int branches = 0;
    for (int i = 0; i < 10; ++i) {
        if (i == 2) continue;
        if (i == 8) break;
        switch (i % 3) {
            case 0:
                branches += 3;
                break;
            case 1:
                branches += 2;
                break;
            default:
                branches += 1;
        }
    }
    if (branches != 16 || fibonacci(8) != 21) return 4;

    volatile int a = 7, b = 3;
    if (VM_ADD(a, b) != 10 || VM_SUB(a, b) != 4) return 5;
    if (VM_MUL(a, b) != 21 || VM_DIV(a, b) != 2 || VM_MOD(a, b) != 1) return 6;
    if (VM_XOR(a, b) != 4 || VM_AND(a, b) != 3 || VM_OR(a, b) != 7) return 7;
    if (!VM_EQU(VM_ADD(a, b), 10) || VM_SHL(b, 2) != 12 || VM_SHR(a, 1) != 3) return 8;
    if (fabsl(VM_ADD_DBL(1.25, 2.5) - 3.75) > 1e-10) return 9;

    char buffer[64], *end;
    char *hidden = HIDE_STRING("TinyCC protected bundle");
    strcpy(buffer, hidden);
    if (strlen(buffer) != 23 || strcmp(buffer, hidden)) return 10;
    memcpy(buffer, HIDE_STRING("1234"), 5);
    if (strtol(buffer, &end, 10) != 1234 || *end) return 11;
    if (fabs(sin(0.0)) > 1e-10 || fabs(sqrt(81.0) - 9.0) > 1e-10) return 12;

    char *heap = malloc(64);
    if (!heap) return 13;
    memset(heap, 42, 64);
    int valid = heap[0] == 42 && heap[63] == 42;
    free(heap);
    if (!valid) return 14;

    if (!GetModuleHandleA("kernel32.dll")) return 15;
    SetLastError(123);
    if (GetLastError() != 123) return 16;
    int result = 0;
    HANDLE thread = CreateThread(0, 0, worker, &result, 0, 0);
    if (!thread) return 17;
    DWORD wait = WaitForSingleObject(thread, 10000);
    CloseHandle(thread);
    if (wait != WAIT_OBJECT_0 || result != 21) return 18;
    return 0;
}

#ifndef OBFH_TEST_DLL
int main(int argc, char **argv) {
    for (int input = 0; input <= 1; ++input) {
        int result = obfh_bundle_check(input);
        if (result) {
            printf("EXE check failed: %d\n", result);
            return result;
        }
    }
    if (argc != 2) return 19;
    HMODULE dll = LoadLibraryA(argv[1]);
    if (!dll) return 20;
    typedef int(__cdecl * check_fn)(int);
    check_fn check = (check_fn)GetProcAddress(dll, "obfh_bundle_check");
    int status = check ? (check(0) | check(1)) : 21;
    FreeLibrary(dll);
    if (status) {
        printf("DLL check failed: %d\n", status);
        return status;
    }
    puts("OBFUS_EXE_DLL_PASS");
    return 0;
}
#endif
