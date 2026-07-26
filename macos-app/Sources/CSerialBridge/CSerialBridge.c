#include "CSerialBridge.h"

#include <errno.h>
#include <fcntl.h>
#include <IOKit/serial/ioss.h>
#include <poll.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

int32_t cr_serial_open(const char *path, uint32_t baud_rate) {
    int descriptor = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (descriptor < 0) {
        return -errno;
    }

    struct termios options;
    if (tcgetattr(descriptor, &options) < 0) {
        int saved_errno = errno;
        close(descriptor);
        return -saved_errno;
    }

    cfmakeraw(&options);
    options.c_cflag &= ~(CSIZE | PARENB | CSTOPB | CRTSCTS);
    options.c_cflag |= CS8 | CLOCAL | CREAD;
    options.c_cc[VMIN] = 0;
    options.c_cc[VTIME] = 0;
    cfsetspeed(&options, B9600);

    if (tcsetattr(descriptor, TCSANOW, &options) < 0) {
        int saved_errno = errno;
        close(descriptor);
        return -saved_errno;
    }

    speed_t speed = (speed_t)baud_rate;
    if (ioctl(descriptor, IOSSIOSPEED, &speed) < 0) {
        int saved_errno = errno;
        close(descriptor);
        return -saved_errno;
    }

    int modem_bits = TIOCM_DTR | TIOCM_RTS;
    (void)ioctl(descriptor, TIOCMBIS, &modem_bits);
    (void)tcflush(descriptor, TCIOFLUSH);
    return descriptor;
}

int32_t cr_serial_close(int32_t descriptor) {
    if (descriptor < 0) {
        return 0;
    }
    int modem_bits = TIOCM_DTR | TIOCM_RTS;
    (void)ioctl(descriptor, TIOCMBIC, &modem_bits);
    return close(descriptor);
}

ssize_t cr_serial_read(int32_t descriptor, void *buffer, size_t length) {
    return read(descriptor, buffer, length);
}

ssize_t cr_serial_write_all(
    int32_t descriptor,
    const void *buffer,
    size_t length,
    int32_t timeout_milliseconds
) {
    const uint8_t *bytes = (const uint8_t *)buffer;
    size_t total = 0;

    while (total < length) {
        ssize_t written = write(descriptor, bytes + total, length - total);
        if (written > 0) {
            total += (size_t)written;
            continue;
        }
        if (written < 0 && errno == EINTR) {
            continue;
        }
        if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            struct pollfd poll_descriptor = {
                .fd = descriptor,
                .events = POLLOUT,
                .revents = 0
            };
            int result = poll(&poll_descriptor, 1, timeout_milliseconds);
            if (result > 0) {
                continue;
            }
            errno = result == 0 ? ETIMEDOUT : errno;
        }
        return total > 0 ? (ssize_t)total : -1;
    }

    return (ssize_t)total;
}
