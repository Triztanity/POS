package com.batmanstarexpress.afcs

import android.app.Activity
import android.content.Intent
import android.content.IntentFilter
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
  companion object {
    private const val TAG = "NFC_READER"
    private const val CHANNEL = "com.example.untitled/nfc"
    private const val EVENT_CHANNEL = "com.example.untitled/nfc_tags"
    private const val DEVICE_CHANNEL = "com.example.untitled/device"
  }

  private lateinit var methodChannel: MethodChannel
  private var eventSink: EventChannel.EventSink? = null
  private var nfcAdapter: NfcAdapter? = null
  private var readerCallback: NfcAdapter.ReaderCallback? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    methodChannel.setMethodCallHandler { call, result ->
      when (call.method) {
        "enableReaderMode" -> {
          enableNfcReaderMode()
          result.success(null)
        }
        "disableReaderMode" -> {
          disableNfcReaderMode()
          result.success(null)
        }
        else -> {
          result.notImplemented()
        }
      }
    }

    // Expose device identifiers to Flutter (best-effort)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
        .setMethodCallHandler { call, result ->
          when (call.method) {
            "getDeviceIdentifiers" -> {
              try {
                val androidId = android.provider.Settings.Secure.getString(contentResolver, android.provider.Settings.Secure.ANDROID_ID)
                val serial: String = try {
                  if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    android.os.Build.getSerial()
                  } else {
                    android.os.Build.SERIAL ?: "unknown"
                  }
                } catch (se: Exception) {
                  try {
                    android.os.Build.SERIAL ?: "unknown"
                  } catch (e: Exception) {
                    "unknown"
                  }
                }

                val manufacturer = android.os.Build.MANUFACTURER ?: "unknown"
                val model = android.os.Build.MODEL ?: "unknown"

                val map: Map<String, String> = mapOf(
                  "androidId" to (androidId ?: "unknown"),
                  "serial" to serial,
                  "manufacturer" to manufacturer,
                  "model" to model
                )
                result.success(map)
              } catch (e: Exception) {
                result.error("DEVICE_ERROR", "Failed to read device identifiers: ${e.message}", null)
              }
            }
            else -> result.notImplemented()
          }
        }

    EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
        .setStreamHandler(object : EventChannel.StreamHandler {
          override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
            Log.d(TAG, "EventChannel listener attached")
          }

          override fun onCancel(arguments: Any?) {
            eventSink = null
            Log.d(TAG, "EventChannel listener detached")
          }
        })

    nfcAdapter = NfcAdapter.getDefaultAdapter(this)
    if (nfcAdapter == null) {
      Log.e(TAG, "NFC not supported on this device")
    }
  }

  private fun enableNfcReaderMode() {
    if (nfcAdapter == null) {
      Log.e(TAG, "NFC adapter is null")
      return
    }

    readerCallback = NfcAdapter.ReaderCallback { tag ->
      val uid = tag.id
      val uidHex = uid.joinToString("") { "%02X".format(it) }
      Log.d(TAG, "Tag detected: $uidHex")
      
      // Send UID to Flutter via EventChannel on the UI thread
      try {
        val event = mapOf("uid" to uidHex)
        runOnUiThread {
          try {
            eventSink?.success(event)
          } catch (inner: Exception) {
            Log.e(TAG, "Error sending tag to Flutter on UI thread: ${inner.message}")
          }
        }
      } catch (e: Exception) {
        Log.e(TAG, "Error preparing tag event: ${e.message}")
      }
    }

    try {
      val flags = NfcAdapter.FLAG_READER_NFC_A or
                  NfcAdapter.FLAG_READER_NFC_B or
                  NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK
      nfcAdapter?.enableReaderMode(this, readerCallback, flags, null)
      Log.d(TAG, "Reader mode enabled")
    } catch (e: Exception) {
      Log.e(TAG, "Error enabling reader mode: ${e.message}")
    }
  }

  private fun disableNfcReaderMode() {
    try {
      nfcAdapter?.disableReaderMode(this)
      readerCallback = null
      Log.d(TAG, "Reader mode disabled")
    } catch (e: Exception) {
      Log.e(TAG, "Error disabling reader mode: ${e.message}")
    }
  }

  override fun onResume() {
    super.onResume()
    enableNfcReaderMode()
  }

  override fun onPause() {
    disableNfcReaderMode()
    super.onPause()
  }
}
