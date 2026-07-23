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
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
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
    private lateinit var baudSpinner: Spinner
    private lateinit var terminalView: TextView
    private lateinit var terminalScroll: ScrollView
    private lateinit var inputField: EditText
    private lateinit var sendButton: Button

    private val baudRates = listOf(9600, 19200, 38400, 57600, 115200, 230400, 500000)

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
        baudSpinner = findViewById(R.id.baudSpinner)
        terminalView = findViewById(R.id.terminalView)
        terminalScroll = findViewById(R.id.terminalScroll)
        inputField = findViewById(R.id.inputField)
        sendButton = findViewById(R.id.sendButton)

        val adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_item,
            baudRates.map { "$it baud" }
        )
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        baudSpinner.adapter = adapter
        baudSpinner.setSelection(0) // 9600, the firmware's SERIAL_MONITOR speed

        connectButton.setOnClickListener { if (connected) disconnect() else connect() }
        sendButton.setOnClickListener { sendInput() }
        clearButton.setOnClickListener { terminalView.text = "" }
        captureButton.setOnClickListener { toggleCapture() }
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
    }

    private fun disconnect() {
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
    }

    private fun sendInput() {
        val text = inputField.text.toString()
        val serialPort = port
        if (serialPort == null || !connected) {
            Toast.makeText(this, R.string.status_not_connected, Toast.LENGTH_SHORT).show()
            return
        }
        try {
            serialPort.write((text + "\n").toByteArray(Charsets.ISO_8859_1), WRITE_WAIT_MILLIS)
            appendTerminal("> $text\n")
            inputField.setText("")
        } catch (e: Exception) {
            appendTerminal("\n[write failed: ${e.message}]\n")
            disconnect()
        }
    }

    // SerialInputOutputManager.Listener — called on the I/O thread
    override fun onNewData(data: ByteArray) {
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
            appendTerminal(String(data, Charsets.ISO_8859_1))
            updateCaptureUi()
        }
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
