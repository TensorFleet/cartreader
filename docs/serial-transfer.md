# OSCR serial ROM transfer

The `SERIAL_MONITOR` build uses 500,000 baud and keeps the SD card as the
authoritative dump. After a ROM operation reaches its `Press Button` prompt, a host
may send the single byte `T` to request the most recently completed ROM.

## Protocol version 1

The reader sends an ASCII header followed immediately by the declared number of raw
ROM bytes:

```text
OSCRXFER1\r\n
NAME:<file name>\r\n
SIZE:<decimal byte count>\r\n
DATA\r\n
<exactly SIZE binary bytes>
\r\nOSCRXFER1 END <eight-digit CRC32>\r\n
```

The CRC32 uses the standard reflected polynomial `0xEDB88320`, initial value
`0xFFFFFFFF`, and final XOR `0xFFFFFFFF`. Hosts must consume exactly `SIZE` binary
bytes before parsing the footer. A partial file must not be published when the
connection fails or the two checksums differ.

Errors are returned as one line:

```text
OSCRXFER1 ERR NO_ROM
OSCRXFER1 ERR FILE_NOT_FOUND
```

The transfer command is accepted only at the post-operation wait prompt so it cannot
be confused with ordinary single-byte menu navigation.
