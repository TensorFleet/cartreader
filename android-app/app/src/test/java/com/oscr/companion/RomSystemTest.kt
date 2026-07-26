package com.oscr.companion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RomSystemTest {
    @Test
    fun resolvesUniqueExtensions() {
        assertEquals(RomSystem.SNES, RomSystem.resolve("game.sfc", null))
        assertEquals(RomSystem.GAME_BOY_ADVANCE, RomSystem.resolve("game.gba", null))
        assertEquals(RomSystem.NINTENDO_64, RomSystem.resolve("game.z64", null))
    }

    @Test
    fun selectedSystemDisambiguatesBin() {
        assertEquals(RomSystem.GENESIS, RomSystem.resolve("game.bin", RomSystem.GENESIS))
        assertNull(RomSystem.resolve("game.bin", null))
    }

    @Test
    fun mapsFirmwareMenuLabels() {
        assertEquals(RomSystem.SNES, RomSystem.fromMenuLabel("Super Nintendo/SFC"))
        assertEquals(RomSystem.GAME_BOY_ADVANCE, RomSystem.fromMenuLabel("Game Boy Advance"))
        assertEquals(RomSystem.GAME_GEAR, RomSystem.fromMenuLabel("GameGear Retrode"))
        assertEquals(RomSystem.GAME_GEAR, RomSystem.fromMenuLabel("GameGear Retron3in1"))
    }
}
