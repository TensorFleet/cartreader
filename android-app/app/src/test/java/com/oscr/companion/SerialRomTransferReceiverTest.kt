package com.oscr.companion

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.util.zip.CRC32

class SerialRomTransferReceiverTest {

    @Test
    fun keepsOutputOpenUntilChecksumFooterArrives() {
        class CloseTrackingOutputStream : OutputStream() {
            val bytes = ByteArrayOutputStream()
            var closed = false

            override fun write(value: Int) = bytes.write(value)
            override fun write(data: ByteArray, offset: Int, length: Int) =
                bytes.write(data, offset, length)
            override fun close() {
                closed = true
            }
        }

        val output = CloseTrackingOutputStream()
        var finished: Boolean? = null
        val receiver = SerialRomTransferReceiver {
            SerialRomTransferReceiver.Target(output, "content://rom/test.sfc") { finished = it }
        }

        val payloadResult = receiver.consume(
            "OSCRXFER1\r\nNAME:test.sfc\r\nSIZE:9\r\nDATA\r\n123456789".toByteArray()
        )

        assertEquals(9L, receiver.bytesReceived)
        assertEquals(false, output.closed)
        assertEquals(null, finished)
        assertTrue(payloadResult.events.any { it is SerialRomTransferReceiver.Event.Progress })

        val footerResult = receiver.consume("\r\nOSCRXFER1 END CBF43926\r\n".toByteArray())

        assertEquals(true, output.closed)
        assertEquals(true, finished)
        assertTrue(footerResult.events.any { it is SerialRomTransferReceiver.Event.Completed })
        assertArrayEquals("123456789".toByteArray(), output.bytes.toByteArray())
    }

    @Test
    fun waitsForFooterPastBufferedPadding() {
        val output = ByteArrayOutputStream()
        val receiver = SerialRomTransferReceiver {
            SerialRomTransferReceiver.Target(output, "content://rom/test.sfc") { }
        }

        receiver.consume(
            "OSCRXFER1\r\nNAME:test.sfc\r\nSIZE:9\r\nDATA\r\n123456789".toByteArray()
        )
        val paddingResult = receiver.consume(ByteArray(16 * 1024))
        val footerResult = receiver.consume("\r\nOSCRXFER1 END CBF43926\r\n".toByteArray())

        assertTrue(paddingResult.events.none { it is SerialRomTransferReceiver.Event.Failed })
        assertTrue(footerResult.events.any { it is SerialRomTransferReceiver.Event.Completed })
        assertArrayEquals("123456789".toByteArray(), output.toByteArray())
    }

    @Test
    fun verifiesHeaderChecksumWithoutWaitingForFooter() {
        val output = ByteArrayOutputStream()
        var finished: Boolean? = null
        val receiver = SerialRomTransferReceiver {
            SerialRomTransferReceiver.Target(output, "content://rom/test.sfc") { finished = it }
        }

        val result = receiver.consume(
            (
                "OSCRXFER1\r\nNAME:test.sfc\r\nSIZE:9\r\n" +
                    "CRC32:CBF43926\r\nDATA\r\n123456789"
                ).toByteArray()
        )

        assertEquals(true, finished)
        assertTrue(result.events.any {
            it is SerialRomTransferReceiver.Event.Completed && it.crc32 == 0xCBF43926L
        })
        assertArrayEquals("123456789".toByteArray(), output.toByteArray())
    }

    @Test
    fun receivesFragmentedTransferAndVerifiesCrc() {
        val output = ByteArrayOutputStream()
        var finished: Boolean? = null
        val receiver = SerialRomTransferReceiver {
            SerialRomTransferReceiver.Target(output, "content://rom/test.sfc") { finished = it }
        }
        val packet = (
            "OSCRXFER1\r\nNAME:test.sfc\r\nSIZE:9\r\nDATA\r\n" +
                "123456789\r\nOSCRXFER1 END CBF43926\r\nNEXT\r\n"
            ).toByteArray()

        val events = mutableListOf<SerialRomTransferReceiver.Event>()
        val passthrough = ByteArrayOutputStream()
        packet.toList().chunked(7).forEach { bytes ->
            val result = receiver.consume(bytes.toByteArray())
            events += result.events
            passthrough.write(result.passthrough)
        }

        assertArrayEquals("123456789".toByteArray(), output.toByteArray())
        assertEquals(true, finished)
        assertTrue(events.any {
            it is SerialRomTransferReceiver.Event.Completed && it.crc32 == 0xCBF43926L
        })
        assertEquals("NEXT\r\n", passthrough.toString())
    }

    @Test
    fun rejectsBadCrcAndMarksTargetFailed() {
        val output = ByteArrayOutputStream()
        var finished: Boolean? = null
        val receiver = SerialRomTransferReceiver {
            SerialRomTransferReceiver.Target(output, "content://rom/test.gb") { finished = it }
        }
        val packet = (
            "OSCRXFER1\r\nNAME:test.gb\r\nSIZE:3\r\nDATA\r\n" +
                "abc\r\nOSCRXFER1 END 00000000\r\n"
            ).toByteArray()

        val result = receiver.consume(packet)

        assertEquals(false, finished)
        assertTrue(result.events.any {
            it is SerialRomTransferReceiver.Event.Failed && "checksum mismatch" in it.message
        })
    }

    @Test
    fun bufferedReadsThrottleProgressAndKeepFinalTail() {
        val payload = ByteArray(3 * 1024 * 1024) { index -> index.toByte() }
        val checksum = CRC32().apply { update(payload) }.value
        val packet = ByteArrayOutputStream().apply {
            write("OSCRXFER1\r\nNAME:test.sfc\r\nSIZE:${payload.size}\r\nDATA\r\n".toByteArray())
            write(payload)
            write("\r\nOSCRXFER1 END %08X\r\n".format(checksum).toByteArray())
            write(ByteArray(16 * 1024))
        }.toByteArray()
        val output = ByteArrayOutputStream()
        val receiver = SerialRomTransferReceiver {
            SerialRomTransferReceiver.Target(output, "content://rom/test.sfc") { }
        }

        val events = mutableListOf<SerialRomTransferReceiver.Event>()
        var offset = 0
        while (offset < packet.size) {
            val end = minOf(offset + 16 * 1024, packet.size)
            events += receiver.consume(packet.copyOfRange(offset, end)).events
            offset = end
        }

        assertArrayEquals(payload, output.toByteArray())
        assertTrue(events.last() is SerialRomTransferReceiver.Event.Completed)
        assertTrue(events.count { it is SerialRomTransferReceiver.Event.Progress } <= 97)
    }
}
