package com.oscr.companion

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import com.hoho.android.usbserial.util.SerialInputOutputManager
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : AppCompatActivity(), SerialInputOutputManager.Listener {

    companion object {
        private const val ACTION_USB_PERMISSION = "com.oscr.companion.USB_PERMISSION"
        private const val REQUEST_STORAGE_PERMISSION = 1
        private const val REQUEST_ROM_STORAGE_PERMISSION = 2
        private const val WRITE_WAIT_MILLIS = 2000
        private const val MAX_TERMINAL_CHARS = 100000
    }

    private lateinit var usbManager: UsbManager

    private var port: UsbSerialPort? = null
    private var ioManager: SerialInputOutputManager? = null
    private var connected = false

    private val captureLock = Any()
    private var captureStream: OutputStream? = null
    private var captureBytes: Long = 0
    private var captureName: String? = null

    private lateinit var statusText: TextView
    private lateinit var captureStatusText: TextView
    private lateinit var connectButton: Button
    private lateinit var captureButton: Button
    private lateinit var clearButton: Button
    private lateinit var guideButton: Button
    private lateinit var settingsButton: Button
    private lateinit var baudSpinner: Spinner
    private lateinit var terminalView: TextView
    private lateinit var terminalScroll: ScrollView
    private lateinit var inputField: EditText
    private lateinit var sendButton: Button
    private lateinit var chipScroll: HorizontalScrollView
    private lateinit var chipContainer: LinearLayout
    private lateinit var romActionContainer: LinearLayout
    private lateinit var romStatusText: TextView
    private lateinit var romProgress: ProgressBar
    private lateinit var downloadButton: Button
    private lateinit var downloadPlayButton: Button
    private lateinit var openRomButton: Button

    private val baudRates = listOf(9600, 19200, 38400, 57600, 115200, 230400, 500000)

    // Firmware menus print one option per line as "N)Label" (N is 0-6), followed by
    // a "type a number(0-6)" prompt; the selection is read back as a single byte.
    private val menuOptionRegex = Regex("^\\s*([0-6])\\)\\s*(.*?)\\s*$")
    private val lineBuffer = StringBuilder()
    private val menuOptions = mutableListOf<Pair<String, String>>()
    private var selectedRomSystem: RomSystem? = null
    private var romReadPending = false
    private var romReadReady = false
    private val romReadBuffer = StringBuilder()

    @Volatile private var transferReceiver: SerialRomTransferReceiver? = null
    private var launchAfterTransfer = false
    private var pendingPermissionLaunch = false

    private val openRomLauncher = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            try {
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: SecurityException) {
                // Some document providers grant access only for the current task.
            }
            launchRom(uri, displayNameFor(uri), selectedRomSystem)
        }
    }

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                ACTION_USB_PERMISSION -> {
                    val granted =
                        intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    if (granted) {
                        connect()
                    } else {
                        setStatus(getString(R.string.status_permission_denied))
                    }
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    if (connected) {
                        appendTerminal("\n[device detached]\n")
                        disconnect()
                    }
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        usbManager = getSystemService(Context.USB_SERVICE) as UsbManager

        statusText = findViewById(R.id.statusText)
        captureStatusText = findViewById(R.id.captureStatusText)
        connectButton = findViewById(R.id.connectButton)
        captureButton = findViewById(R.id.captureButton)
        clearButton = findViewById(R.id.clearButton)
        guideButton = findViewById(R.id.guideButton)
        settingsButton = findViewById(R.id.settingsButton)
        baudSpinner = findViewById(R.id.baudSpinner)
        terminalView = findViewById(R.id.terminalView)
        terminalScroll = findViewById(R.id.terminalScroll)
        inputField = findViewById(R.id.inputField)
        sendButton = findViewById(R.id.sendButton)
        chipScroll = findViewById(R.id.chipScroll)
        chipContainer = findViewById(R.id.chipContainer)
        romActionContainer = findViewById(R.id.romActionContainer)
        romStatusText = findViewById(R.id.romStatusText)
        romProgress = findViewById(R.id.romProgress)
        downloadButton = findViewById(R.id.downloadButton)
        downloadPlayButton = findViewById(R.id.downloadPlayButton)
        openRomButton = findViewById(R.id.openRomButton)

        val adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_item,
            baudRates.map { "$it baud" }
        )
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        baudSpinner.adapter = adapter
        baudSpinner.setSelection(baudRates.lastIndex) // serial-transfer firmware: 500,000

        connectButton.setOnClickListener { if (connected) disconnect() else connect() }
        sendButton.setOnClickListener { sendInput() }
        clearButton.setOnClickListener { terminalView.text = "" }
        captureButton.setOnClickListener { toggleCapture() }
        guideButton.setOnClickListener { showGuide() }
        settingsButton.setOnClickListener { showEmulatorSettings() }
        downloadButton.setOnClickListener { startRomDownload(playWhenFinished = false) }
        downloadPlayButton.setOnClickListener { startRomDownload(playWhenFinished = true) }
        openRomButton.setOnClickListener { openExistingRom() }
        inputField.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND) {
                sendInput()
                true
            } else {
                false
            }
        }

        val filter = IntentFilter().apply {
            addAction(ACTION_USB_PERMISSION)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        ContextCompat.registerReceiver(
            this, usbReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED
        )

        setStatus(getString(R.string.status_disconnected))
        updateCaptureUi()
        updateRomActions()

        if (intent?.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) {
            connect()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == UsbManager.ACTION_USB_DEVICE_ATTACHED && !connected) {
            connect()
        }
    }

    override fun onDestroy() {
        transferReceiver?.cancel()
        transferReceiver = null
        stopCapture(silent = true)
        disconnect()
        unregisterReceiver(usbReceiver)
        super.onDestroy()
    }

    private fun selectedBaud(): Int = baudRates[baudSpinner.selectedItemPosition]

    private fun findDevice(): Pair<UsbDevice, UsbSerialPort>? {
        val drivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager)
        if (drivers.isEmpty()) return null
        val driver = drivers[0]
        return Pair(driver.device, driver.ports[0])
    }

    private fun connect() {
        if (connected) return
        val found = findDevice()
        if (found == null) {
            setStatus(getString(R.string.status_no_device))
            return
        }
        val (device, serialPort) = found

        if (!usbManager.hasPermission(device)) {
            setStatus(getString(R.string.status_requesting_permission))
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            }
            val permissionIntent = PendingIntent.getBroadcast(
                this, 0, Intent(ACTION_USB_PERMISSION).setPackage(packageName), flags
            )
            usbManager.requestPermission(device, permissionIntent)
            return
        }

        val connection = usbManager.openDevice(device)
        if (connection == null) {
            setStatus(getString(R.string.status_open_failed))
            return
        }

        try {
            serialPort.open(connection)
            serialPort.setParameters(
                selectedBaud(), 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE
            )
            try {
                serialPort.setDTR(true)
                serialPort.setRTS(true)
            } catch (_: UnsupportedOperationException) {
                // Some adapters don't support control lines; not fatal.
            }
        } catch (e: Exception) {
            setStatus(getString(R.string.status_open_failed) + ": " + e.message)
            try {
                serialPort.close()
            } catch (_: Exception) {
            }
            return
        }

        port = serialPort
        val manager = SerialInputOutputManager(serialPort, this)
        ioManager = manager
        Executors.newSingleThreadExecutor().submit(manager)

        connected = true
        connectButton.text = getString(R.string.disconnect)
        baudSpinner.isEnabled = false
        setStatus(
            getString(
                R.string.status_connected_fmt,
                device.productName ?: "USB device",
                selectedBaud()
            )
        )
        appendTerminal("[connected at ${selectedBaud()} baud]\n")
        updateRomActions()
    }

    private fun disconnect() {
        transferReceiver?.cancel()
        transferReceiver = null
        connected = false
        ioManager?.stop()
        ioManager = null
        try {
            port?.close()
        } catch (_: Exception) {
        }
        port = null
        connectButton.text = getString(R.string.connect)
        baudSpinner.isEnabled = true
        setStatus(getString(R.string.status_disconnected))
        updateRomActions()
    }

    private fun sendInput() {
        val text = inputField.text.toString()
        if (text.isEmpty()) return
        if (sendText(text)) {
            inputField.setText("")
        }
    }

    // The firmware reads menu selections as single bytes, so nothing extra
    // (no newline) must be appended to what the user sends.
    private fun sendText(text: String): Boolean {
        val serialPort = port
        if (serialPort == null || !connected) {
            Toast.makeText(this, R.string.status_not_connected, Toast.LENGTH_SHORT).show()
            return false
        }
        return try {
            serialPort.write(text.toByteArray(Charsets.ISO_8859_1), WRITE_WAIT_MILLIS)
            appendTerminal("> $text\n")
            true
        } catch (e: Exception) {
            appendTerminal("\n[write failed: ${e.message}]\n")
            disconnect()
            false
        }
    }

    // SerialInputOutputManager.Listener — called on the I/O thread
    override fun onNewData(data: ByteArray) {
        val receiver = transferReceiver
        if (receiver != null) {
            val result = receiver.consume(data)
            if (result.events.any {
                    it is SerialRomTransferReceiver.Event.Completed ||
                        it is SerialRomTransferReceiver.Event.Failed
                }) {
                transferReceiver = null
            }
            runOnUiThread {
                handleTransferEvents(result.events)
                if (result.passthrough.isNotEmpty()) {
                    val text = String(result.passthrough, Charsets.ISO_8859_1)
                    appendTerminal(text)
                    processIncoming(text)
                }
            }
            return
        }

        synchronized(captureLock) {
            val stream = captureStream
            if (stream != null) {
                try {
                    stream.write(data)
                    captureBytes += data.size
                } catch (e: IOException) {
                    runOnUiThread {
                        appendTerminal("\n[capture write failed: ${e.message}]\n")
                        stopCapture(silent = true)
                    }
                }
            }
        }
        runOnUiThread {
            val text = String(data, Charsets.ISO_8859_1)
            appendTerminal(text)
            processIncoming(text)
            updateCaptureUi()
        }
    }

    private fun processIncoming(text: String) {
        if (romReadPending) {
            romReadBuffer.append(text)
            if (romReadBuffer.length > 12000) {
                romReadBuffer.delete(0, romReadBuffer.length - 8000)
            }
            val lower = romReadBuffer.toString().lowercase()
            val markers = listOf(
                "press button", "press any button", "finished successfully",
                "finished reading", " -> ok"
            )
            if (markers.any { it in lower }) {
                romReadPending = false
                romReadReady = true
                romStatusText.setText(R.string.rom_dump_finished)
                updateRomActions()
            }
        }
        for (ch in text) {
            if (ch == '\n') {
                handleLine(lineBuffer.toString().trimEnd('\r'))
                lineBuffer.setLength(0)
            } else {
                lineBuffer.append(ch)
                // Guard against endless lines of binary data
                if (lineBuffer.length > 500) lineBuffer.setLength(0)
            }
        }
    }

    private fun handleLine(line: String) {
        val match = menuOptionRegex.matchEntire(line)
        if (match != null) {
            val key = match.groupValues[1]
            val label = match.groupValues[2]
            if (label.isEmpty()) return
            // Menus always start printing at option 0
            if (key == "0") menuOptions.clear()
            menuOptions.removeAll { it.first == key }
            menuOptions.add(Pair(key, label))
            showMenuChips()
            return
        }
        if (line.startsWith("Enter first letter", ignoreCase = true)) {
            showLetterChips()
        }
    }

    private fun showMenuChips() {
        chipContainer.removeAllViews()
        for ((key, label) in menuOptions) {
            addChip("$key  $label") { performMenuAction(key, label) }
        }
        if (menuOptions.isNotEmpty()) {
            addChip(getString(R.string.chip_page_up)) { sendText("u") }
            addChip(getString(R.string.chip_page_down)) { sendText("d") }
        }
        chipScroll.visibility = if (chipContainer.childCount > 0) View.VISIBLE else View.GONE
        chipScroll.scrollTo(0, 0)
    }

    private fun performMenuAction(key: String, label: String) {
        RomSystem.fromMenuLabel(label)?.let { selectedRomSystem = it }
        val lower = label.lowercase()
        if ("read rom" in lower || "dump rom" in lower) {
            romReadPending = true
            romReadReady = false
            romReadBuffer.setLength(0)
            romStatusText.setText(R.string.rom_reading)
            romActionContainer.visibility = View.VISIBLE
            updateRomActions()
        }
        sendText(key)
    }

    private fun updateRomActions() {
        val downloading = transferReceiver != null
        downloadButton.isEnabled = connected && romReadReady && !downloading
        downloadPlayButton.isEnabled = connected && romReadReady && !downloading
        openRomButton.isEnabled = !downloading
        romProgress.visibility = if (downloading) View.VISIBLE else View.GONE
        if (romReadReady || romReadPending || downloading) {
            romActionContainer.visibility = View.VISIBLE
        }
    }

    private fun startRomDownload(playWhenFinished: Boolean) {
        if (!connected || !romReadReady) {
            Toast.makeText(this, "Finish a ROM read while connected first.", Toast.LENGTH_LONG).show()
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.WRITE_EXTERNAL_STORAGE
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingPermissionLaunch = playWhenFinished
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                REQUEST_ROM_STORAGE_PERMISSION
            )
            return
        }

        launchAfterTransfer = playWhenFinished
        transferReceiver = SerialRomTransferReceiver { name -> createRomDownloadTarget(name) }
        romProgress.progress = 0
        romStatusText.setText(R.string.rom_requesting)
        updateRomActions()
        if (!sendText("T")) {
            transferReceiver?.cancel()
            transferReceiver = null
            updateRomActions()
        }
    }

    private fun createRomDownloadTarget(deviceName: String): SerialRomTransferReceiver.Target {
        val safeName = File(deviceName).name.ifBlank { "OSCR-ROM.bin" }.replace(':', '-')
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS + "/CartReader/ROMs"
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("could not create Downloads/CartReader/ROMs/$safeName")
            val stream = contentResolver.openOutputStream(uri)
                ?: throw IOException("could not open $safeName")
            SerialRomTransferReceiver.Target(
                BufferedOutputStream(stream),
                uri.toString()
            ) { success ->
                if (success) {
                    contentResolver.update(uri, ContentValues().apply {
                        put(MediaStore.MediaColumns.IS_PENDING, 0)
                    }, null, null)
                } else {
                    contentResolver.delete(uri, null, null)
                }
            }
        } else {
            val directory = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "CartReader/ROMs"
            )
            if (!directory.exists() && !directory.mkdirs()) {
                throw IOException("could not create ${directory.absolutePath}")
            }
            val file = uniqueFile(directory, safeName)
            val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
            SerialRomTransferReceiver.Target(
                BufferedOutputStream(FileOutputStream(file)),
                uri.toString()
            ) { success -> if (!success) file.delete() }
        }
    }

    private fun uniqueFile(directory: File, name: String): File {
        var candidate = File(directory, name)
        var suffix = 2
        val extension = name.substringAfterLast('.', "")
        val stem = if (extension.isEmpty()) name else name.dropLast(extension.length + 1)
        while (candidate.exists()) {
            val nextName = if (extension.isEmpty()) "$stem-$suffix" else "$stem-$suffix.$extension"
            candidate = File(directory, nextName)
            suffix++
        }
        return candidate
    }

    private fun handleTransferEvents(events: List<SerialRomTransferReceiver.Event>) {
        for (event in events) {
            when (event) {
                is SerialRomTransferReceiver.Event.Started -> {
                    romStatusText.text = getString(
                        R.string.rom_downloading_fmt,
                        event.name,
                        formatBytes(event.size)
                    )
                    romProgress.visibility = View.VISIBLE
                }
                is SerialRomTransferReceiver.Event.Progress -> {
                    val percent = if (event.size == 0L) 0 else ((event.received * 100) / event.size).toInt()
                    romProgress.progress = percent
                    romStatusText.text = getString(R.string.rom_downloading_percent_fmt, percent)
                }
                is SerialRomTransferReceiver.Event.Completed -> {
                    romProgress.progress = 100
                    romProgress.visibility = View.GONE
                    romStatusText.text = getString(
                        R.string.rom_downloaded_verified_fmt,
                        event.name,
                        event.crc32
                    )
                    appendTerminal("\n[ROM downloaded: ${event.name} — CRC32 %08X]\n".format(event.crc32))
                    Toast.makeText(
                        this,
                        "Saved Downloads/CartReader/ROMs/${event.name}",
                        Toast.LENGTH_LONG
                    ).show()
                    if (launchAfterTransfer) {
                        launchRom(Uri.parse(event.reference), event.name, selectedRomSystem)
                    }
                }
                is SerialRomTransferReceiver.Event.Failed -> {
                    romProgress.visibility = View.GONE
                    romStatusText.setText(R.string.rom_transfer_failed)
                    AlertDialog.Builder(this)
                        .setTitle("ROM transfer")
                        .setMessage(event.message)
                        .setPositiveButton(android.R.string.ok, null)
                        .show()
                }
            }
        }
        updateRomActions()
    }

    private fun formatBytes(bytes: Long): String {
        val mib = bytes.toDouble() / (1024.0 * 1024.0)
        return if (mib >= 1) String.format(Locale.US, "%.1f MiB", mib) else "$bytes bytes"
    }

    private fun showLetterChips() {
        chipContainer.removeAllViews()
        for (c in "#ABCDEFGHIJKLMNOPQRSTUVWXYZ") {
            addChip(c.toString()) { sendText(c.toString()) }
        }
        chipScroll.visibility = View.VISIBLE
        chipScroll.scrollTo(0, 0)
    }

    private fun addChip(label: String, onClick: () -> Unit) {
        val button = Button(this)
        button.text = label
        button.isAllCaps = false
        button.textSize = 13f
        button.minWidth = 0
        button.minimumWidth = 0
        button.minHeight = 0
        button.minimumHeight = 0
        val params = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        params.marginEnd = (6 * resources.displayMetrics.density).toInt()
        button.layoutParams = params
        val padH = (14 * resources.displayMetrics.density).toInt()
        val padV = (4 * resources.displayMetrics.density).toInt()
        button.setPadding(padH, padV, padH, padV)
        button.setOnClickListener { onClick() }
        chipContainer.addView(button)
    }

    private fun showEmulatorSettings() {
        val systems = RomSystem.entries.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("Configure emulator for…")
            .setItems(systems.map { it.displayName }.toTypedArray()) { _, index ->
                showEmulatorChoices(systems[index])
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun showEmulatorChoices(system: RomSystem) {
        val choices = mutableListOf<Pair<String, String>>()
        choices += "RetroArch — ${system.retroArchCore.removeSuffix("_libretro_android.so")}" to "retroarch"
        choices += "Always show Android app chooser" to "chooser"

        val sampleUri = Uri.parse("content://$packageName.files/sample.${system.extensions.first()}")
        val queryIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(sampleUri, "application/octet-stream")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val installed = packageManager.queryIntentActivities(
            queryIntent,
            PackageManager.MATCH_DEFAULT_ONLY
        ).distinctBy { it.activityInfo.packageName }
            .sortedBy { it.loadLabel(packageManager).toString().lowercase() }
        for (activity in installed) {
            val packageId = activity.activityInfo.packageName
            if (packageId != packageName && packageId !in listOf("com.retroarch", "com.retroarch.aarch64")) {
                choices += "${activity.loadLabel(packageManager)} ($packageId)" to packageId
            }
        }

        val preferences = getSharedPreferences("emulators", Context.MODE_PRIVATE)
        val current = preferences.getString(system.name, "retroarch")
        val checked = choices.indexOfFirst { it.second == current }.coerceAtLeast(0)
        AlertDialog.Builder(this)
            .setTitle(system.displayName)
            .setSingleChoiceItems(choices.map { it.first }.toTypedArray(), checked) { dialog, which ->
                preferences.edit().putString(system.name, choices[which].second).apply()
                Toast.makeText(this, "${system.displayName}: ${choices[which].first}", Toast.LENGTH_SHORT).show()
                dialog.dismiss()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun openExistingRom() {
        openRomLauncher.launch(arrayOf("application/octet-stream", "application/zip"))
    }

    private fun displayNameFor(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return uri.lastPathSegment ?: "ROM"
    }

    private fun launchRom(uri: Uri, fileName: String, preferredSystem: RomSystem?) {
        val system = RomSystem.resolve(fileName, preferredSystem)
        if (system == null) {
            AlertDialog.Builder(this)
                .setTitle("Choose cartridge type first")
                .setMessage("The .${fileName.substringAfterLast('.', "")} extension is ambiguous or unsupported. Select its console in the OSCR menu, then try again.")
                .setPositiveButton(android.R.string.ok, null)
                .show()
            return
        }

        val preference = getSharedPreferences("emulators", Context.MODE_PRIVATE)
            .getString(system.name, "retroarch") ?: "retroarch"
        try {
            val intent = if (preference == "retroarch") {
                val retroArchPackage = listOf("com.retroarch.aarch64", "com.retroarch")
                    .firstOrNull { isPackageInstalled(it) }
                    ?: throw IllegalStateException("RetroArch is not installed. Install it or choose another emulator under Emulators.")
                Intent().apply {
                    setClassName(
                        retroArchPackage,
                        "com.retroarch.browser.retroactivity.RetroActivityFuture"
                    )
                    putExtra("ROM", uri.toString())
                    putExtra("LIBRETRO", system.retroArchCore)
                    clipData = android.content.ClipData.newRawUri("OSCR ROM", uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            } else {
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/octet-stream")
                    clipData = android.content.ClipData.newRawUri("OSCR ROM", uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    if (preference != "chooser") setPackage(preference)
                }
            }
            startActivity(if (preference == "chooser") Intent.createChooser(intent, "Open ${system.displayName} ROM with") else intent)
        } catch (e: Exception) {
            AlertDialog.Builder(this)
                .setTitle("Could not launch emulator")
                .setMessage(e.message ?: e.javaClass.simpleName)
                .setPositiveButton(android.R.string.ok, null)
                .show()
        }
    }

    private fun isPackageInstalled(packageId: String): Boolean = try {
        packageManager.getPackageInfo(packageId, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private fun showGuide() {
        AlertDialog.Builder(this)
            .setTitle(R.string.guide_title)
            .setMessage(R.string.guide_text)
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    override fun onRunError(e: Exception) {
        runOnUiThread {
            if (connected) {
                appendTerminal("\n[connection lost: ${e.message}]\n")
                disconnect()
            }
        }
    }

    private fun toggleCapture() {
        if (captureStream != null) {
            stopCapture(silent = false)
        } else {
            startCapture()
        }
    }

    private fun startCapture() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.WRITE_EXTERNAL_STORAGE
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                REQUEST_STORAGE_PERMISSION
            )
            return
        }

        val name = "oscr_capture_" +
            SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()) + ".log"
        try {
            val rawStream: OutputStream = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                    put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        Environment.DIRECTORY_DOWNLOADS + "/CartReader"
                    )
                }
                val uri = contentResolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
                ) ?: throw IOException("could not create file in Downloads")
                contentResolver.openOutputStream(uri)
                    ?: throw IOException("could not open file in Downloads")
            } else {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOWNLOADS
                    ),
                    "CartReader"
                )
                if (!dir.exists() && !dir.mkdirs()) {
                    throw IOException("could not create " + dir.absolutePath)
                }
                FileOutputStream(File(dir, name))
            }
            synchronized(captureLock) {
                captureStream = BufferedOutputStream(rawStream)
                captureBytes = 0
                captureName = name
            }
            appendTerminal("[capture started: Downloads/CartReader/$name]\n")
        } catch (e: Exception) {
            Toast.makeText(
                this,
                getString(R.string.capture_failed_fmt, e.message),
                Toast.LENGTH_LONG
            ).show()
        }
        updateCaptureUi()
    }

    private fun stopCapture(silent: Boolean) {
        val name: String?
        val bytes: Long
        synchronized(captureLock) {
            val stream = captureStream ?: return
            try {
                stream.flush()
                stream.close()
            } catch (_: IOException) {
            }
            captureStream = null
            name = captureName
            bytes = captureBytes
            captureName = null
        }
        if (!silent) {
            appendTerminal("[capture stopped: $name, $bytes bytes]\n")
            Toast.makeText(
                this,
                getString(R.string.capture_saved_fmt, name, bytes),
                Toast.LENGTH_LONG
            ).show()
        }
        updateCaptureUi()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_STORAGE_PERMISSION &&
            grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            startCapture()
        } else if (requestCode == REQUEST_ROM_STORAGE_PERMISSION &&
            grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            startRomDownload(pendingPermissionLaunch)
        }
    }

    private fun updateCaptureUi() {
        if (captureStream != null) {
            captureButton.text = getString(R.string.stop_capture)
            captureStatusText.visibility = View.VISIBLE
            captureStatusText.text =
                getString(R.string.capture_status_fmt, captureName, captureBytes)
        } else {
            captureButton.text = getString(R.string.start_capture)
            captureStatusText.visibility = View.GONE
        }
    }

    private fun setStatus(text: String) {
        statusText.text = text
    }

    private fun appendTerminal(text: String) {
        terminalView.append(text)
        val len = terminalView.text.length
        if (len > MAX_TERMINAL_CHARS) {
            terminalView.text = terminalView.text.subSequence(len - MAX_TERMINAL_CHARS / 2, len)
        }
        terminalScroll.post { terminalScroll.fullScroll(View.FOCUS_DOWN) }
    }
}
