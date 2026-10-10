#include <windows.h>
#include <winsock2.h>
#include <mmsystem.h>
#include <d3d9.h>
#include <stdio.h>
#include <math.h>
#include <stdint.h>
#include <stdatomic.h>
int main(void) {
    WSADATA data;
    atomic_int value = 1;
    if (atomic_fetch_add(&value, 2) != 1 || atomic_load(&value) != 3) return 1;
    if (sizeof(void *) != sizeof(uintptr_t) || sqrt(81.0) != 9.0) return 2;
    if (!GetModuleHandleA("kernel32.dll")) return 3;
    if (WSAStartup(MAKEWORD(2, 2), &data)) return 4;
    if (WSACleanup()) return 5;
    DWORD handles;
    if (!GetProcessHandleCount(GetCurrentProcess(), &handles) || !handles) return 6;
    char temp[MAX_PATH], name[MAX_PATH];
    if (!GetTempPathA(sizeof(temp), temp) || !GetTempFileNameA(temp, "tcb", 0, name)) return 7;
    HANDLE file = CreateFileA(name, GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, 0, 0);
    LARGE_INTEGER size;
    int valid = file != INVALID_HANDLE_VALUE && GetFileSizeEx(file, &size) && size.QuadPart == 0;
    if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
    DeleteFileA(name);
    if (!valid) return 8;
    if (RegCloseKey((HKEY)0) == ERROR_SUCCESS) return 9;
    puts("TINYC_BUILDER_PASS");
    return 0;
}
