package com.oscr.companion

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream

class SerialRomTransferReceiverTest {
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
}
