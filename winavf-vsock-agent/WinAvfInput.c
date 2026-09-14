/*
 * Minimal WinPE user-mode endpoint for the WinAVF vsock transport.
 *
 * It intentionally does not create a kernel driver, modify a signed driver,
 * or assume an interactive desktop.  The first runtime milestone is the
 * bidirectional HELLO.  KEY packets call SendInput only when an interactive
 * WinPE desktop actually exists.
 */
#define WIN32_LEAN_AND_MEAN
#define WIN32_NO_STATUS
#include <windows.h>
#include <winsock2.h>

#define WINAVF_PORT 4050U
#define IOCTL_VIOSOCK_GET_AF 0x0801300CUL
#define VIOSOCK_DEVICE L"\\\\??\\Viosock"

typedef struct _WINAVF_SOCKADDR_VM {
    ADDRESS_FAMILY svm_family;
    USHORT svm_reserved1;
    UINT svm_port;
    UINT svm_cid;
} WINAVF_SOCKADDR_VM;

typedef struct _WINAVF_PACKET {
    CHAR magic[4];       /* "WVI1" */
    ULONG sequence;      /* little-endian */
    USHORT virtualKey;   /* Windows VK value */
    UCHAR type;          /* 1 = keyboard */
    UCHAR action;        /* 1 = down, 2 = up */
    ULONG reserved;
} WINAVF_PACKET;

typedef struct _WINAVF_REPLY {
    CHAR magic[4];       /* "WVO1" */
    ULONG sequence;      /* copied from request */
    ULONG status;        /* 0 = accepted; Win32 error otherwise */
    ULONG capabilities;  /* bit 0 = SendInput command implemented */
} WINAVF_REPLY;

typedef UINT (WINAPI *SEND_INPUT_FN)(UINT, LPINPUT, int);

static void Clear(void *buffer, SIZE_T length) {
    volatile BYTE *next = (volatile BYTE *)buffer;
    while (length-- != 0) *next++ = 0;
}

static void SetMagic(CHAR destination[4], const CHAR source[4]) {
    destination[0] = source[0];
    destination[1] = source[1];
    destination[2] = source[2];
    destination[3] = source[3];
}

static BOOL MagicEquals(const CHAR left[4], const CHAR right[4]) {
    return left[0] == right[0] && left[1] == right[1] &&
           left[2] == right[2] && left[3] == right[3];
}

static BOOL ReadExact(SOCKET socket, void *buffer, int length) {
    CHAR *next = (CHAR *)buffer;
    while (length > 0) {
        int result = recv(socket, next, length, 0);
        if (result <= 0) return FALSE;
        next += result;
        length -= result;
    }
    return TRUE;
}

static BOOL WriteExact(SOCKET socket, const void *buffer, int length) {
    const CHAR *next = (const CHAR *)buffer;
    while (length > 0) {
        int result = send(socket, next, length, 0);
        if (result <= 0) return FALSE;
        next += result;
        length -= result;
    }
    return TRUE;
}

static ADDRESS_FAMILY GetViosockAddressFamily(void) {
    DWORD family = AF_UNSPEC;
    DWORD returned = 0;
    HANDLE device = CreateFileW(VIOSOCK_DEVICE, GENERIC_READ, FILE_SHARE_READ,
                                NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (device == INVALID_HANDLE_VALUE) return AF_UNSPEC;
    if (!DeviceIoControl(device, IOCTL_VIOSOCK_GET_AF, NULL, 0, &family,
                         sizeof(family), &returned, NULL)) {
        family = AF_UNSPEC;
    }
    CloseHandle(device);
    return (ADDRESS_FAMILY)family;
}

static DWORD InjectKey(USHORT virtualKey, UCHAR action) {
    HMODULE user32;
    SEND_INPUT_FN sendInput;
    INPUT input;

    if (action != 1 && action != 2) return ERROR_INVALID_DATA;
    user32 = LoadLibraryW(L"user32.dll");
    if (user32 == NULL) return GetLastError();
    sendInput = (SEND_INPUT_FN)GetProcAddress(user32, "SendInput");
    if (sendInput == NULL) {
        DWORD error = GetLastError();
        FreeLibrary(user32);
        return error ? error : ERROR_PROC_NOT_FOUND;
    }
    Clear(&input, sizeof(input));
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = virtualKey;
    input.ki.dwFlags = action == 2 ? KEYEVENTF_KEYUP : 0;
    if (sendInput(1, &input, sizeof(input)) != 1) {
        DWORD error = GetLastError();
        FreeLibrary(user32);
        return error ? error : ERROR_GEN_FAILURE;
    }
    FreeLibrary(user32);
    return ERROR_SUCCESS;
}

static DWORD ServeClient(SOCKET client) {
    WINAVF_REPLY reply;
    WINAVF_PACKET packet;

    Clear(&reply, sizeof(reply));
    SetMagic(reply.magic, "WVH1");
    reply.capabilities = 1;
    if (!WriteExact(client, &reply, sizeof(reply))) return ERROR_WRITE_FAULT;

    for (;;) {
        DWORD status;
        if (!ReadExact(client, &packet, sizeof(packet))) return ERROR_BROKEN_PIPE;
        if (!MagicEquals(packet.magic, "WVI1")) {
            return ERROR_INVALID_DATA;
        }
        status = packet.type == 1 ? InjectKey(packet.virtualKey, packet.action)
                                  : ERROR_NOT_SUPPORTED;
        Clear(&reply, sizeof(reply));
        SetMagic(reply.magic, "WVO1");
        reply.sequence = packet.sequence;
        reply.status = status;
        reply.capabilities = 1;
        if (!WriteExact(client, &reply, sizeof(reply))) return ERROR_WRITE_FAULT;
    }
}

static DWORD AgentMain(void) {
    WSADATA data;
    ADDRESS_FAMILY family;
    WINAVF_SOCKADDR_VM address;
    SOCKET listener;

    if (WSAStartup(MAKEWORD(2, 2), &data) != 0) return 10;
    /* PnP can bind the signed viosock device after startnet launches us. */
    family = AF_UNSPEC;
    for (DWORD attempt = 0; attempt != 600 && family == AF_UNSPEC; ++attempt) {
        family = GetViosockAddressFamily();
        if (family == AF_UNSPEC) Sleep(100);
    }
    if (family == AF_UNSPEC) { WSACleanup(); return 11; }

    listener = socket(family, SOCK_STREAM, 0);
    if (listener == INVALID_SOCKET) { WSACleanup(); return 12; }
    ZeroMemory(&address, sizeof(address));
    address.svm_family = family;
    address.svm_port = WINAVF_PORT;
    address.svm_cid = (UINT)-1; /* VMADDR_CID_ANY */
    if (bind(listener, (const SOCKADDR *)&address, sizeof(address)) == SOCKET_ERROR ||
        listen(listener, 1) == SOCKET_ERROR) {
        closesocket(listener);
        WSACleanup();
        return 13;
    }

    for (;;) {
        SOCKET client = accept(listener, NULL, NULL);
        if (client == INVALID_SOCKET) break;
        ServeClient(client);
        closesocket(client);
    }
    closesocket(listener);
    WSACleanup();
    return 0;
}

void WINAPI WinMainCRTStartup(void) {
    ExitProcess(AgentMain());
}
