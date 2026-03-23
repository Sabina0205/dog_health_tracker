package com.example.dog_health_tracker

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val storageChannel = "pet_health/storage"
    private val prefs by lazy {
        getSharedPreferences("pet_health_storage", Context.MODE_PRIVATE)
    }

    private var pendingPhotoResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            storageChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "loadState" -> result.success(prefs.getString(KEY_STATE_JSON, null))
                "saveState" -> handleSaveState(call.arguments as? String, result)
                "pickDogPhoto" -> handlePickDogPhoto(result)
                "requestNotificationPermission" -> handleNotificationPermission(result)
                "scheduleNotifications" -> handleScheduleNotifications(call.arguments, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleSaveState(payload: String?, result: MethodChannel.Result) {
        prefs.edit().putString(KEY_STATE_JSON, payload ?: "").apply()
        result.success(null)
    }

    private fun handlePickDogPhoto(result: MethodChannel.Result) {
        pendingPhotoResult?.error(
            "photo_pick_in_progress",
            "Photo picker is already open.",
            null,
        )
        pendingPhotoResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
        }
        startActivityForResult(
            Intent.createChooser(intent, "Vyber fotku psa"),
            REQUEST_PICK_DOG_PHOTO,
        )
    }

    private fun handleNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }

        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }

        pendingPermissionResult?.error(
            "notification_permission_in_progress",
            "Notification permission request already in progress.",
            null,
        )
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATION_PERMISSION,
        )
    }

    private fun handleScheduleNotifications(
        rawArguments: Any?,
        result: MethodChannel.Result,
    ) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        cancelScheduledNotifications(alarmManager)

        val reminders = rawArguments as? List<*> ?: emptyList<Any>()
        val scheduledIds = mutableSetOf<String>()
        for (item in reminders) {
            val reminder = item as? Map<*, *> ?: continue
            val id = (reminder["id"] as? Number)?.toInt() ?: continue
            val title = reminder["title"] as? String ?: continue
            val body = reminder["body"] as? String ?: continue
            val timestamp = (reminder["timestamp"] as? Number)?.toLong() ?: continue

            scheduleNotification(
                alarmManager = alarmManager,
                id = id,
                title = title,
                body = body,
                timestamp = timestamp,
            )
            scheduledIds.add(id.toString())
        }

        prefs.edit().putStringSet(KEY_SCHEDULED_NOTIFICATION_IDS, scheduledIds).apply()
        result.success(null)
    }

    private fun scheduleNotification(
        alarmManager: AlarmManager,
        id: Int,
        title: String,
        body: String,
        timestamp: Long,
    ) {
        val intent = Intent(this, ReminderReceiver::class.java)
            .putExtra(ReminderReceiver.EXTRA_NOTIFICATION_ID, id)
            .putExtra(ReminderReceiver.EXTRA_NOTIFICATION_TITLE, title)
            .putExtra(ReminderReceiver.EXTRA_NOTIFICATION_BODY, body)

        val pendingIntent = PendingIntent.getBroadcast(
            this,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                timestamp,
                pendingIntent,
            )
        } else {
            alarmManager.set(
                AlarmManager.RTC_WAKEUP,
                timestamp,
                pendingIntent,
            )
        }
    }

    private fun cancelScheduledNotifications(alarmManager: AlarmManager) {
        val scheduledIds = prefs.getStringSet(KEY_SCHEDULED_NOTIFICATION_IDS, emptySet()).orEmpty()
        for (idText in scheduledIds) {
            val id = idText.toIntOrNull() ?: continue
            val intent = Intent(this, ReminderReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }
    }

    private fun copyPickedPhotoToAppStorage(uri: Uri): String {
        val extension = contentResolver.getType(uri)
            ?.substringAfterLast('/', "jpg")
            ?.lowercase()
            ?.ifBlank { "jpg" }
            ?: "jpg"
        val photosDir = File(filesDir, "dog_photos").apply { mkdirs() }
        val destination = File(
            photosDir,
            "dog_${System.currentTimeMillis()}.$extension",
        )

        contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "Unable to open selected image." }
            FileOutputStream(destination).use { output ->
                input.copyTo(output)
            }
        }

        return destination.absolutePath
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != REQUEST_PICK_DOG_PHOTO) {
            return
        }

        val result = pendingPhotoResult ?: return
        pendingPhotoResult = null

        if (resultCode != RESULT_OK) {
            result.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.success(null)
            return
        }

        try {
            result.success(copyPickedPhotoToAppStorage(uri))
        } catch (error: Exception) {
            result.error("photo_pick_failed", error.localizedMessage, null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != REQUEST_NOTIFICATION_PERMISSION) {
            return
        }

        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        result.success(granted)
    }

    private companion object {
        const val KEY_STATE_JSON = "state_json"
        const val KEY_SCHEDULED_NOTIFICATION_IDS = "scheduled_notification_ids"
        const val REQUEST_PICK_DOG_PHOTO = 1001
        const val REQUEST_NOTIFICATION_PERMISSION = 1002
    }
}
