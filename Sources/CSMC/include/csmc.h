#ifndef CSMC_H
#define CSMC_H

#include <stdint.h>

// Thin C bridge to AppleSMC. Implemented in C so the ABI-sensitive `SMCParamStruct`
// uses the exact C layout the kernel expects (Swift's struct layout differs).
// Reads are unprivileged; `csmc_write` requires root and is only ever called from the
// privileged fan-control helper, never from the main (user) app.

// Opens the AppleSMC connection. Returns the connection handle, or 0 on failure.
unsigned int csmc_open(void);

// Closes a connection opened with csmc_open().
void csmc_close(unsigned int conn);

// Reads a key (FourCC as a UInt32). Returns 0 on success and fills out the SMC
// data type (FourCC), byte size, and up to 32 raw bytes. Returns non-zero on failure.
int csmc_read(unsigned int conn, uint32_t key,
              uint32_t *out_type, uint32_t *out_size, uint8_t out_bytes[32]);

// Returns the key (FourCC) at an enumeration index, or 0 on failure.
uint32_t csmc_key_from_index(unsigned int conn, uint32_t index);

// Writes `size` bytes to a key (FourCC as a UInt32). Requires the connection to have been
// opened by a root process. Returns 0 on success, non-zero on failure.
int csmc_write(unsigned int conn, uint32_t key, uint32_t size, const uint8_t *bytes);

#endif /* CSMC_H */
