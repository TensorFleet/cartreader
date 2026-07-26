package com.oscr.companion

import java.io.OutputStream
import java.util.zip.CRC32

class SerialRomTransferReceiver(
    private val targetFactory: (String) -> Target
) {
    data class Target(
        val output: OutputStream,
        val reference: String,
        val finish: (Boolean) -> Unit
    )

    sealed class Event {
        data class Started(val name: String, val size: Long) : Event()
        data class Progress(val received: Long, val size: Long) : Event()
        data class Completed(val name: String, val reference: String, val crc32: Long) : Event()
        data class Failed(val message: String) : Event()
    }

    data class ConsumeResult(
        val events: List<Event>,
        val passthrough: ByteArray = byteArrayOf()
    )

    private enum class State { HEADER, DATA, FOOTER, FINISHED }

    private var state = State.HEADER
    private var pending = byteArrayOf()
    private var target: Target? = null
    private var fileName = ""
    private var expectedSize = 0L
    private var receivedSize = 0L
    private val crc = CRC32()

    fun consume(input: ByteArray): ConsumeResult {
        if (state == State.FINISHED) return ConsumeResult(emptyList(), input)
        pending += input
        val events = mutableListOf<Event>()

        var progressed = true
        while (progressed) {
            progressed = false
            when (state) {
                State.HEADER -> {
                    val errorPrefix = "OSCRXFER1 ERR ".toByteArray()
                    val errorIndex = pending.indexOf(errorPrefix)
                    if (errorIndex >= 0) {
                        val newline = pending.indexOf(byteArrayOf('\n'.code.toByte()), errorIndex)
                        if (newline >= 0) {
                            val reason = pending.copyOfRange(errorIndex + errorPrefix.size, newline)
                                .toString(Charsets.UTF_8).trim()
                            fail(deviceError(reason), events)
                        }
                        continue
                    }

                    val protocolIndex = pending.indexOf("OSCRXFER1".toByteArray())
                    if (protocolIndex < 0) {
                        if (pending.size > 4096) fail("The reader did not send a valid OSCRXFER1 header.", events)
                        continue
                    }
                    if (protocolIndex > 0) pending = pending.copyOfRange(protocolIndex, pending.size)
                    val dataMarker = "\r\nDATA\r\n".toByteArray()
                    val markerIndex = pending.indexOf(dataMarker)
                    if (markerIndex < 0) continue

                    val header = pending.copyOfRange(0, markerIndex).toString(Charsets.UTF_8)
                    val name = header.lineValue("NAME")
                    val size = header.lineValue("SIZE")?.toLongOrNull()
                    if (name.isNullOrBlank() || size == null || size <= 0) {
                        fail("The reader sent an invalid transfer header.", events)
                        continue
                    }
                    try {
                        target = targetFactory(name)
                    } catch (e: Exception) {
                        fail("Could not create the ROM download: ${e.message}", events)
                        continue
                    }
                    fileName = name
                    expectedSize = size
                    pending = pending.copyOfRange(markerIndex + dataMarker.size, pending.size)
                    state = State.DATA
                    events += Event.Started(name, size)
                    progressed = true
                }

                State.DATA -> {
                    val remaining = expectedSize - receivedSize
                    if (remaining == 0L) {
                        target?.output?.flush()
                        target?.output?.close()
                        state = State.FOOTER
                        progressed = true
                        continue
                    }
                    if (pending.isEmpty()) continue
                    val count = minOf(remaining, pending.size.toLong()).toInt()
                    val chunk = pending.copyOfRange(0, count)
                    try {
                        target?.output?.write(chunk)
                    } catch (e: Exception) {
                        fail("Writing the ROM download failed: ${e.message}", events)
                        continue
                    }
                    crc.update(chunk)
                    receivedSize += count
                    pending = pending.copyOfRange(count, pending.size)
                    events += Event.Progress(receivedSize, expectedSize)
                    progressed = true
                }

                State.FOOTER -> {
                    val footerIndex = pending.indexOf("OSCRXFER1 END ".toByteArray())
                    if (footerIndex < 0) {
                        if (pending.size > 256) fail("The reader did not send a valid transfer checksum.", events)
                        continue
                    }
                    val newline = pending.indexOf(byteArrayOf('\n'.code.toByte()), footerIndex)
                    if (newline < 0) continue
                    val footer = pending.copyOfRange(footerIndex, newline).toString(Charsets.UTF_8).trim()
                    val deviceCRC = footer.substringAfter("OSCRXFER1 END ", "").toLongOrNull(16)
                    if (deviceCRC == null) {
                        fail("The reader sent a malformed transfer checksum.", events)
                        continue
                    }
                    val localCRC = crc.value
                    if (deviceCRC != localCRC) {
                        fail(
                            "ROM transfer checksum mismatch (reader %08X, Android %08X). Please retry."
                                .format(deviceCRC, localCRC),
                            events
                        )
                        continue
                    }
                    target?.finish?.invoke(true)
                    val reference = target?.reference.orEmpty()
                    pending = pending.copyOfRange(newline + 1, pending.size)
                    events += Event.Completed(fileName, reference, localCRC)
                    state = State.FINISHED
                    return ConsumeResult(events, pending)
                }

                State.FINISHED -> return ConsumeResult(events, pending)
            }
        }
        return ConsumeResult(events)
    }

    fun cancel() {
        try { target?.output?.close() } catch (_: Exception) {}
        target?.finish?.invoke(false)
        state = State.FINISHED
    }

    private fun fail(message: String, events: MutableList<Event>) {
        try { target?.output?.close() } catch (_: Exception) {}
        target?.finish?.invoke(false)
        events += Event.Failed(message)
        state = State.FINISHED
        pending = byteArrayOf()
    }

    private fun deviceError(reason: String): String = when (reason) {
        "NO_ROM" -> "No completed ROM is available. Read a ROM first, then download it at the Press Button prompt."
        "FILE_NOT_FOUND" -> "The completed ROM could not be reopened on the OSCR SD card."
        else -> "The reader rejected the ROM transfer: $reason"
    }

    private fun String.lineValue(name: String): String? {
        val prefix = "$name:"
        return lineSequence().firstOrNull { it.startsWith(prefix) }
            ?.removePrefix(prefix)?.trim()
    }

    private fun ByteArray.indexOf(needle: ByteArray, fromIndex: Int = 0): Int {
        if (needle.isEmpty()) return fromIndex.coerceAtMost(size)
        outer@ for (index in fromIndex..size - needle.size) {
            for (offset in needle.indices) {
                if (this[index + offset] != needle[offset]) continue@outer
            }
            return index
        }
        return -1
    }
}
