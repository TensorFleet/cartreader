#ifndef C_SERIAL_BRIDGE_H
#define C_SERIAL_BRIDGE_H

#include <stdint.h>
#include <sys/types.h>

int32_t cr_serial_open(const char *path, uint32_t baud_rate);
int32_t cr_serial_close(int32_t descriptor);
ssize_t cr_serial_read(int32_t descriptor, void *buffer, size_t length);
ssize_t cr_serial_write_all(
    int32_t descriptor,
    const void *buffer,
    size_t length,
    int32_t timeout_milliseconds
);

#endif
