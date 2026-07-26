package com.oscr.companion

enum class RomSystem(
    val displayName: String,
    val extensions: Set<String>,
    val retroArchCore: String
) {
    GAME_BOY("Game Boy / Game Boy Color", setOf("gb", "gbc"), "gambatte_libretro_android.so"),
    GAME_BOY_ADVANCE("Game Boy Advance", setOf("gba"), "mgba_libretro_android.so"),
    NES("NES / Famicom", setOf("nes", "unf", "unif", "bin"), "mesen_libretro_android.so"),
    SNES("Super Nintendo / Super Famicom", setOf("sfc", "smc", "bs"), "snes9x_libretro_android.so"),
    NINTENDO_64("Nintendo 64", setOf("z64", "n64", "v64"), "mupen64plus_next_gles3_libretro_android.so"),
    GENESIS("Mega Drive / Genesis", setOf("md", "gen", "bin"), "genesis_plus_gx_libretro_android.so"),
    MASTER_SYSTEM("Master System / Mark III", setOf("sms"), "genesis_plus_gx_libretro_android.so"),
    GAME_GEAR("Game Gear", setOf("gg"), "genesis_plus_gx_libretro_android.so"),
    SG1000("SG-1000", setOf("sg"), "genesis_plus_gx_libretro_android.so"),
    PC_ENGINE("PC Engine / TurboGrafx-16", setOf("pce"), "mednafen_pce_fast_libretro_android.so"),
    WONDERSWAN("WonderSwan", setOf("ws", "wsc"), "mednafen_wswan_libretro_android.so"),
    NEO_GEO_POCKET("Neo Geo Pocket", setOf("ngp", "ngc"), "mednafen_ngp_libretro_android.so"),
    INTELLIVISION("Intellivision", setOf("int", "rom", "bin"), "freeintv_libretro_android.so"),
    COLECOVISION("ColecoVision", setOf("col", "rom", "bin"), "gearcoleco_libretro_android.so"),
    VIRTUAL_BOY("Virtual Boy", setOf("vb"), "mednafen_vb_libretro_android.so"),
    SUPERVISION("Watara Supervision", setOf("sv"), "potator_libretro_android.so"),
    ATARI_2600("Atari 2600", setOf("a26", "bin"), "stella_libretro_android.so"),
    ODYSSEY_2("Magnavox Odyssey 2", setOf("bin"), "o2em_libretro_android.so"),
    MSX("MSX", setOf("rom", "mx1", "mx2", "bin"), "bluemsx_libretro_android.so"),
    POKEMON_MINI("Pokémon Mini", setOf("min"), "pokemini_libretro_android.so"),
    COMMODORE_64("Commodore 64", setOf("crt", "bin"), "vice_x64_libretro_android.so"),
    ATARI_5200("Atari 5200", setOf("a52", "bin"), "a5200_libretro_android.so"),
    ATARI_7800("Atari 7800", setOf("a78"), "prosystem_libretro_android.so"),
    ATARI_JAGUAR("Atari Jaguar", setOf("j64", "jag"), "virtualjaguar_libretro_android.so"),
    ATARI_LYNX("Atari Lynx", setOf("lnx"), "mednafen_lynx_libretro_android.so"),
    VECTREX("Vectrex", setOf("vec", "bin"), "vecx_libretro_android.so"),
    ATARI_8_BIT("Atari 8-bit", setOf("xex", "atr", "car", "bin"), "atari800_libretro_android.so");

    companion object {
        fun fromMenuLabel(label: String): RomSystem? {
            val title = label.lowercase()
            return when {
                "game boy advance" in title -> GAME_BOY_ADVANCE
                "game boy (color)" in title || title.trim() == "game boy" -> GAME_BOY
                "nes/famicom" in title -> NES
                "super nintendo" in title || title.trim() == "sfc" -> SNES
                "nintendo 64" in title -> NINTENDO_64
                "mega drive" in title || "genesis" in title -> GENESIS
                "sms/gg" in title || "master system" in title || "mark iii" in title -> MASTER_SYSTEM
                "game gear" in title -> GAME_GEAR
                "sg-1000" in title -> SG1000
                "pc engine" in title || "tg16" in title -> PC_ENGINE
                "wonderswan" in title -> WONDERSWAN
                "neogeo pocket" in title || "neo geo pocket" in title -> NEO_GEO_POCKET
                "intellivision" in title -> INTELLIVISION
                "colecovision" in title -> COLECOVISION
                "virtual boy" in title -> VIRTUAL_BOY
                "watara supervision" in title -> SUPERVISION
                "atari 2600" in title -> ATARI_2600
                "odyssey 2" in title -> ODYSSEY_2
                "pokemon mini" in title -> POKEMON_MINI
                "commodore 64" in title -> COMMODORE_64
                "atari 5200" in title -> ATARI_5200
                "atari 7800" in title -> ATARI_7800
                "atari jaguar" in title -> ATARI_JAGUAR
                "atari lynx" in title -> ATARI_LYNX
                "vectrex" in title -> VECTREX
                "atari 8-bit" in title -> ATARI_8_BIT
                "msx" in title -> MSX
                else -> null
            }
        }

        fun resolve(fileName: String, preferred: RomSystem?): RomSystem? {
            val extension = fileName.substringAfterLast('.', "").lowercase()
            val matches = entries.filter { extension in it.extensions }
            if (preferred != null && preferred in matches) return preferred
            return matches.singleOrNull()
        }
    }
}
