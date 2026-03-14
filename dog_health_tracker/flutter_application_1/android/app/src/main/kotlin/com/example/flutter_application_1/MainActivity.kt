package com.example.flutter_application_1

import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "pet_health/storage"
    private val stateFileName = "pet_health_state.json"
    private val reminderPrefsName = "pet_health_reminders"
    private val reminderIdsKey = "scheduled_ids"
    private val reminderChannelId = "pet_health_reminders"
    private val photoRequestCode = 1101

    private var pendingPhotoResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveState" -> saveState(call, result)
                    "loadState" -> loadState(result)
                    "requestNotificationPermission" -> {
                        requestNotificationPermission()
                        result.success(true)
                    }
                    "scheduleNotifications" -> {
                        scheduleNotifications(call, result)
                    }
                    "pickDogPhoto" -> {
                        openPhotoPicker(result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveState(call: MethodCall, result: MethodChannel.Result) {
        val json = call.arguments as? String ?: ""
        try {
            openFileOutput(stateFileName, Context.MODE_PRIVATE).use { stream ->
                stream.write(json.toByteArray())
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("SAVE_ERROR", e.message, null)
        }
    }

    private fun loadState(result: MethodChannel.Result) {
        try {
            val file = File(filesDir, stateFileName)
            if (!file.exists()) {
                result.success(null)
            } else {
                result.success(file.readText())
            }
        } catch (e: Exception) {
            result.error("LOAD_ERROR", e.message, null)
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    private fun openPhotoPicker(result: MethodChannel.Result) {
        if (pendingPhotoResult != null) {
            result.error("PHOTO_PICK_BUSY", "Photo picker is already open.", null)
            return
        }
        pendingPhotoResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            }
            startActivityForResult(intent, photoRequestCode)
        } catch (e: ActivityNotFoundException) {
            pendingPhotoResult = null
            result.error("PHOTO_PICK_ERROR", e.message, null)
        }
    }

    private fun copyImageToAppStorage(uri: Uri): String {
        val imagesDir = File(filesDir, "dog_photos")
        if (!imagesDir.exists()) {
            imagesDir.mkdirs()
        }
        val target = File(imagesDir, "dog_${System.currentTimeMillis()}.jpg")
        contentResolver.openInputStream(uri).use { input ->
            target.outputStream().use { output ->
                if (input == null) {
                    throw IllegalStateException("Unable to read selected image.")
                }
                input.copyTo(output)
            }
        }
        return target.absolutePath
    }

    @Suppress("UNCHECKED_CAST")
    private fun scheduleNotifications(call: MethodCall, result: MethodChannel.Result) {
        val reminders = call.arguments as? List<Map<String, Any?>> ?: emptyList()
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        createNotificationChannel()
        cancelExistingAlarms(alarmManager)

        val scheduledIds = mutableListOf<Int>()
        val now = System.currentTimeMillis()
        for (item in reminders) {
            val id = (item["id"] as? Number)?.toInt() ?: continue
            val title = item["title"] as? String ?: "Dog Health Tracker"
            val body = item["body"] as? String ?: ""
            val timestamp = (item["timestamp"] as? Number)?.toLong() ?: continue
            if (timestamp <= now) {
                continue
            }

            val intent = Intent(this, ReminderReceiver::class.java).apply {
                putExtra("id", id)
                putExtra("title", title)
                putExtra("body", body)
                putExtra("channelId", reminderChannelId)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestamp, pendingIntent)
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, timestamp, pendingIntent)
            }
            scheduledIds.add(id)
        }

        getSharedPreferences(reminderPrefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(reminderIdsKey, scheduledIds.joinToString(","))
            .apply()
        result.success(true)
    }

    private fun cancelExistingAlarms(alarmManager: AlarmManager) {
        val prefs = getSharedPreferences(reminderPrefsName, Context.MODE_PRIVATE)
        val raw = prefs.getString(reminderIdsKey, "") ?: ""
        if (raw.isBlank()) {
            return
        }
        raw.split(",")
            .mapNotNull { it.toIntOrNull() }
            .forEach { id ->
                val intent = Intent(this, ReminderReceiver::class.java)
                val pendingIntent = PendingIntent.getBroadcast(
                    this,
                    id,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.cancel(pendingIntent)
            }
        prefs.edit().remove(reminderIdsKey).apply()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(reminderChannelId) != null) {
            return
        }
        val channel = NotificationChannel(
            reminderChannelId,
            "Dog Health Reminder",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Reminders for upcoming dog health procedures."
        }
        manager.createNotificationChannel(channel)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != photoRequestCode) {
            return
        }
        val result = pendingPhotoResult
        pendingPhotoResult = null
        if (result == null) {
            return
        }
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(null)
            return
        }
        val uri = data.data
        if (uri == null) {
            result.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: Exception) {
            // Ignore if permission cannot be persisted.
        }
        try {
            val copiedPath = copyImageToAppStorage(uri)
            result.success(copiedPath)
        } catch (e: Exception) {
            result.error("PHOTO_PICK_ERROR", e.message, null)
        }
    }
}
