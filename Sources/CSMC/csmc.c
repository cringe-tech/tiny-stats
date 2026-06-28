#include "csmc.h"

#include <string.h>
#include <IOKit/IOKitLib.h>

typedef struct {
    unsigned char  major;
    unsigned char  minor;
    unsigned char  build;
    unsigned char  reserved[1];
    unsigned short release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t  dataAttributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t       key;
    SMCVersion     vers;
    SMCPLimitData  pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t        result;
    uint8_t        status;
    uint8_t        data8;
    uint32_t       data32;
    uint8_t        bytes[32];
} SMCParamStruct;

enum { KERNEL_INDEX_SMC = 2 };
enum { kSMCReadKey = 5, kSMCWriteKey = 6, kSMCGetKeyFromIndex = 8, kSMCGetKeyInfo = 9 };

unsigned int csmc_open(void) {
    io_service_t service =
        IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 0;

    io_connect_t conn = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &conn);
    IOObjectRelease(service);
    if (kr != kIOReturnSuccess) return 0;
    return (unsigned int)conn;
}

void csmc_close(unsigned int conn) {
    if (conn) IOServiceClose((io_connect_t)conn);
}

static kern_return_t smc_call(unsigned int conn, SMCParamStruct *in, SMCParamStruct *out) {
    size_t inSize = sizeof(SMCParamStruct);
    size_t outSize = sizeof(SMCParamStruct);
    return IOConnectCallStructMethod((io_connect_t)conn, KERNEL_INDEX_SMC,
                                     in, inSize, out, &outSize);
}

int csmc_read(unsigned int conn, uint32_t key,
              uint32_t *out_type, uint32_t *out_size, uint8_t out_bytes[32]) {
    SMCParamStruct in, out;

    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key;
    in.data8 = kSMCGetKeyInfo;
    if (smc_call(conn, &in, &out) != kIOReturnSuccess || out.result != 0) return -1;

    uint32_t size = out.keyInfo.dataSize;
    uint32_t type = out.keyInfo.dataType;
    if (size > 32) size = 32;   // the value buffer is fixed at 32 bytes; never report more

    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key;
    in.keyInfo.dataSize = size;
    in.data8 = kSMCReadKey;
    if (smc_call(conn, &in, &out) != kIOReturnSuccess || out.result != 0) return -1;

    if (out_type) *out_type = type;
    if (out_size) *out_size = size;
    if (out_bytes) memcpy(out_bytes, out.bytes, 32);
    return 0;
}

int csmc_write(unsigned int conn, uint32_t key, uint32_t size, const uint8_t *bytes) {
    if (size > 32) return -1;

    // Validate the key exists and learn its expected data size (the kernel rejects writes
    // whose dataSize doesn't match the key's). We keep the caller-supplied byte count but
    // bail if the key can't be queried.
    SMCParamStruct in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key;
    in.data8 = kSMCGetKeyInfo;
    if (smc_call(conn, &in, &out) != kIOReturnSuccess || out.result != 0) return -1;

    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key;
    in.keyInfo.dataSize = size;
    in.data8 = kSMCWriteKey;
    memcpy(in.bytes, bytes, size);
    if (smc_call(conn, &in, &out) != kIOReturnSuccess) return -1;
    return out.result == 0 ? 0 : -2;
}

uint32_t csmc_key_from_index(unsigned int conn, uint32_t index) {
    SMCParamStruct in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.data8 = kSMCGetKeyFromIndex;
    in.data32 = index;
    if (smc_call(conn, &in, &out) != kIOReturnSuccess || out.result != 0) return 0;
    return out.key;
}
