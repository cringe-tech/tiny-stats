// Phase-0 SMC fan-control spike. Standalone, no project deps.
//
// Validates that fan control actually takes effect on this Mac before we build the
// privileged-helper architecture around it. Read-only by default; only writes when
// invoked as `--apply <rpm>`, and ALWAYS restores auto mode (F0Md=0) on exit, including
// on Ctrl-C / SIGTERM.
//
// Build:  clang -framework IOKit -o /tmp/fan_spike Scripts/fan_spike.c
// Read:   /tmp/fan_spike
// Write:  sudo /tmp/fan_spike --apply 4000   (sets fan 0 to ~4000 RPM for 12s, then auto)
//
// Reuses the exact SMCParamStruct layout from Sources/CSMC/csmc.c.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <IOKit/IOKitLib.h>

typedef struct { unsigned char major, minor, build, reserved[1]; unsigned short release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitData;
typedef struct { uint32_t dataSize, dataType; uint8_t dataAttributes; } SMCKeyInfoData;
typedef struct {
    uint32_t key; SMCVersion vers; SMCPLimitData pLimitData; SMCKeyInfoData keyInfo;
    uint8_t result, status, data8; uint32_t data32; uint8_t bytes[32];
} SMCParamStruct;

enum { KERNEL_INDEX_SMC = 2 };
enum { kSMCReadKey = 5, kSMCWriteKey = 6, kSMCGetKeyInfo = 9 };

static io_connect_t g_conn = 0;
static int g_forced = 0;   // whether we put a fan into forced mode (need to restore)
// Original fan-0 state captured before we touch anything, so restore puts it back exactly.
static double g_orig_md = 0;
static double g_orig_tg = 0;
static int g_have_orig = 0;

static uint32_t fourcc(const char *s) {
    return ((uint32_t)s[0] << 24) | ((uint32_t)s[1] << 16) | ((uint32_t)s[2] << 8) | (uint32_t)s[3];
}
static void typestr(uint32_t t, char out[5]) {
    out[0] = (t >> 24) & 0xff; out[1] = (t >> 16) & 0xff;
    out[2] = (t >> 8) & 0xff;  out[3] = t & 0xff; out[4] = 0;
    for (int i = 3; i >= 0 && (out[i] == ' ' || out[i] == 0); i--) out[i] = 0;
}

static kern_return_t call(SMCParamStruct *in, SMCParamStruct *out) {
    size_t outSize = sizeof(SMCParamStruct);
    return IOConnectCallStructMethod(g_conn, KERNEL_INDEX_SMC, in, sizeof(SMCParamStruct), out, &outSize);
}

static int key_info(const char *key, uint32_t *type, uint32_t *size) {
    SMCParamStruct in, out; memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = fourcc(key); in.data8 = kSMCGetKeyInfo;
    if (call(&in, &out) != kIOReturnSuccess || out.result != 0) return -1;
    if (type) *type = out.keyInfo.dataType;
    if (size) *size = out.keyInfo.dataSize;
    return 0;
}

static int read_key(const char *key, uint32_t *type, uint32_t *size, uint8_t bytes[32]) {
    uint32_t t, s; if (key_info(key, &t, &s)) return -1;
    if (s > 32) s = 32;
    SMCParamStruct in, out; memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = fourcc(key); in.keyInfo.dataSize = s; in.data8 = kSMCReadKey;
    if (call(&in, &out) != kIOReturnSuccess || out.result != 0) return -1;
    if (type) *type = t; if (size) *size = s; memcpy(bytes, out.bytes, 32);
    return 0;
}

static int write_key(const char *key, uint32_t size, const uint8_t *bytes) {
    SMCParamStruct in, out; memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = fourcc(key); in.keyInfo.dataSize = size; in.data8 = kSMCWriteKey;
    memcpy(in.bytes, bytes, size > 32 ? 32 : size);
    if (call(&in, &out) != kIOReturnSuccess) return -1;
    return out.result == 0 ? 0 : -2;
}

// Decode raw SMC bytes to double per type (mirrors SMCValue.double).
static double decode(uint32_t type, uint32_t size, const uint8_t *b) {
    char t[5]; typestr(type, t);
    if (!strcmp(t, "flt") && size >= 4) { uint32_t bits = b[0] | (b[1]<<8) | (b[2]<<16) | ((uint32_t)b[3]<<24); float f; memcpy(&f, &bits, 4); return f; }
    if (!strcmp(t, "ui8")) return b[0];
    if (!strcmp(t, "ui16") && size >= 2) return (b[0]<<8) | b[1];
    if (!strcmp(t, "fpe2") && size >= 2) return (double)((b[0]<<8) | b[1]) / 4.0;
    if (!strcmp(t, "fp2e") && size >= 2) return (double)((b[0]<<8) | b[1]) / 16384.0;
    if (!strcmp(t, "sp78") && size >= 2) { int16_t r = (int16_t)((b[0]<<8) | b[1]); return r / 256.0; }
    if (size >= 4) { uint32_t bits = b[0] | (b[1]<<8) | (b[2]<<16) | ((uint32_t)b[3]<<24); float f; memcpy(&f, &bits, 4); return f; }
    return 0;
}

// Encode a double into raw SMC bytes per type. Returns byte count, 0 on unsupported.
static uint32_t encode(uint32_t type, uint32_t size, double v, uint8_t out[32]) {
    char t[5]; typestr(type, t);
    memset(out, 0, 32);
    if (!strcmp(t, "flt")) { float f = (float)v; uint32_t bits; memcpy(&bits, &f, 4); out[0]=bits&0xff; out[1]=(bits>>8)&0xff; out[2]=(bits>>16)&0xff; out[3]=(bits>>24)&0xff; return 4; }
    if (!strcmp(t, "ui8")) { out[0] = (uint8_t)v; return 1; }
    if (!strcmp(t, "ui16")) { uint16_t r = (uint16_t)v; out[0] = (r>>8)&0xff; out[1] = r&0xff; return 2; }
    if (!strcmp(t, "fpe2")) { uint16_t r = (uint16_t)(v * 4.0); out[0] = (r>>8)&0xff; out[1] = r&0xff; return 2; }
    return 0;
}

static void print_key(const char *key) {
    uint32_t type, size; uint8_t b[32];
    if (read_key(key, &type, &size, b)) { printf("  %s : <unavailable>\n", key); return; }
    char t[5]; typestr(type, t);
    printf("  %-4s : %-5s size=%u  value=%.2f\n", key, t, size, decode(type, size, b));
}

static void restore_auto(void) {
    if (!g_forced || !g_conn) return;
    uint32_t type, size; uint8_t b[32];
    // Restore the original Tg first, then the original Md (default 0 = auto if uncaptured).
    if (g_have_orig && read_key("F0Tg", &type, &size, b) == 0) {
        uint8_t enc[32]; uint32_t n = encode(type, size, g_orig_tg, enc);
        if (n) write_key("F0Tg", n, enc);
    }
    if (read_key("F0Md", &type, &size, b) == 0) {
        uint8_t enc[32]; uint32_t n = encode(type, size, g_have_orig ? g_orig_md : 0, enc);
        if (n) write_key("F0Md", n, enc);
    }
    g_forced = 0;
    printf("\nRestored F0Md=%.0f, F0Tg=%.0f (original).\n", g_have_orig ? g_orig_md : 0, g_orig_tg);
}

static void on_signal(int sig) { (void)sig; restore_auto(); _exit(1); }

int main(int argc, char **argv) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) { fprintf(stderr, "AppleSMC not found\n"); return 1; }
    if (IOServiceOpen(svc, mach_task_self(), 0, &g_conn) != kIOReturnSuccess) {
        fprintf(stderr, "IOServiceOpen failed\n"); IOObjectRelease(svc); return 1;
    }
    IOObjectRelease(svc);

    uint32_t ftype, fsize; uint8_t fb[32];
    int nfans = 0;
    if (read_key("FNum", &ftype, &fsize, fb) == 0) nfans = (int)decode(ftype, fsize, fb);
    printf("Fans (FNum): %d\n", nfans);

    printf("\nFan 0 keys (read-only):\n");
    print_key("F0Mn"); print_key("F0Mx"); print_key("F0Md");
    print_key("F0Tg"); print_key("F0Ac");

    if (argc >= 3 && strcmp(argv[1], "--apply") == 0) {
        double rpm = atof(argv[2]);

        // Clamp into [F0Mn, F0Mx] so the spike itself can never command something unsafe.
        uint32_t mnT, mnS, mxT, mxS; uint8_t mnB[32], mxB[32];
        double mn = 0, mx = 1e9;
        if (read_key("F0Mn", &mnT, &mnS, mnB) == 0) mn = decode(mnT, mnS, mnB);
        if (read_key("F0Mx", &mxT, &mxS, mxB) == 0) mx = decode(mxT, mxS, mxB);
        if (rpm < mn) rpm = mn; if (rpm > mx) rpm = mx;

        signal(SIGINT, on_signal); signal(SIGTERM, on_signal);

        // Capture original state so restore puts it back exactly (not a blind Md=0).
        {
            uint32_t t, s; uint8_t b[32];
            if (read_key("F0Md", &t, &s, b) == 0) g_orig_md = decode(t, s, b);
            if (read_key("F0Tg", &t, &s, b) == 0) g_orig_tg = decode(t, s, b);
            g_have_orig = 1;
            printf("\nOriginal state: F0Md=%.0f F0Tg=%.0f\n", g_orig_md, g_orig_tg);
        }

        // F0Md = 1 (forced)
        uint32_t mdT, mdS; uint8_t mdB[32];
        if (read_key("F0Md", &mdT, &mdS, mdB)) { fprintf(stderr, "cannot read F0Md\n"); return 1; }
        uint8_t enc[32]; uint32_t n = encode(mdT, mdS, 1, enc);
        if (!n || write_key("F0Md", n, enc)) { fprintf(stderr, "write F0Md=1 FAILED (need sudo?)\n"); return 1; }
        g_forced = 1;
        printf("\nWrote F0Md=1 (forced). Setting F0Tg=%.0f (clamped to [%.0f, %.0f])...\n", rpm, mn, mx);

        // F0Tg = rpm
        uint32_t tgT, tgS; uint8_t tgB[32];
        if (read_key("F0Tg", &tgT, &tgS, tgB)) { fprintf(stderr, "cannot read F0Tg\n"); restore_auto(); return 1; }
        n = encode(tgT, tgS, rpm, enc);
        if (!n || write_key("F0Tg", n, enc)) { fprintf(stderr, "write F0Tg FAILED\n"); restore_auto(); return 1; }

        printf("Watching F0Ac for 12s (expect it to approach %.0f)...\n", rpm);
        for (int i = 0; i < 12; i++) {
            uint32_t at, as; uint8_t ab[32];
            if (read_key("F0Ac", &at, &as, ab) == 0)
                printf("  t=%2ds  F0Ac=%.0f RPM\n", i, decode(at, as, ab));
            sleep(1);
        }
        restore_auto();
    } else {
        printf("\n(read-only. Run `sudo %s --apply <rpm>` to test writing.)\n", argv[0]);
    }
    return 0;
}
