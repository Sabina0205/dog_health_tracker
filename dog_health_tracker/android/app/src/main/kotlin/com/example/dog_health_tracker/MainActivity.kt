package com.example.dog_health_tracker

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val storageChannel = "pet_health/storage"
    private val externalChannel = "pet_health/external"
    private val prefs by lazy {
        getSharedPreferences("pet_health_storage", Context.MODE_PRIVATE)
    }

    private var pendingPhotoResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingLocationResult: MethodChannel.Result? = null
    private var activeLocationManager: LocationManager? = null
    private var activeLocationListener: LocationListener? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var locationTimeoutRunnable: Runnable? = null

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
                "requestExactAlarmPermission" -> handleExactAlarmPermission(result)
                "scheduleNotifications" -> handleScheduleNotifications(call.arguments, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            externalChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentLocation" -> handleGetCurrentLocation(result)
                "openMapSearch" -> handleOpenMapSearch(call.arguments, result)
                "openExternalUrl" -> handleOpenExternalUrl(call.arguments, result)
                "openDialer" -> handleOpenDialer(call.arguments, result)
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

    private fun handleExactAlarmPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(true)
            return
        }

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (alarmManager.canScheduleExactAlarms()) {
            result.success(true)
            return
        }

        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
            data = Uri.parse("package:$packageName")
        }
        runCatching {
            startActivity(intent)
            result.success(false)
        }.onFailure {
            result.error(
                "exact_alarm_permission_failed",
                "Unable to open exact alarm settings.",
                null,
            )
        }
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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !alarmManager.canScheduleExactAlarms()
            ) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    timestamp,
                    pendingIntent,
                )
            } else {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    timestamp,
                    pendingIntent,
                )
            }
        } else {
            alarmManager.setExact(
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

    private fun handleGetCurrentLocation(result: MethodChannel.Result) {
        if (pendingLocationResult != null) {
            result.error(
                "location_request_in_progress",
                "Location request is already in progress.",
                null,
            )
            return
        }
        pendingLocationResult = result

        if (hasLocationPermission()) {
            requestCurrentLocation()
            return
        }

        requestPermissions(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            REQUEST_LOCATION_PERMISSION,
        )
    }

    private fun hasLocationPermission(): Boolean {
        val fineGranted =
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        val coarseGranted =
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        return fineGranted || coarseGranted
    }

    private fun requestCurrentLocation() {
        val result = pendingLocationResult ?: return
        val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
        ).filter { provider ->
            runCatching { locationManager.isProviderEnabled(provider) }.getOrDefault(false)
        }

        if (providers.isEmpty()) {
            pendingLocationResult = null
            result.error(
                "location_services_disabled",
                "Location services are disabled.",
                null,
            )
            return
        }

        val lastKnownLocation = providers
            .mapNotNull { provider ->
                runCatching { locationManager.getLastKnownLocation(provider) }.getOrNull()
            }
            .maxByOrNull { location -> location.time }

        if (lastKnownLocation != null && System.currentTimeMillis() - lastKnownLocation.time < 10 * 60 * 1000) {
            pendingLocationResult = null
            result.success(locationToMap(lastKnownLocation))
            return
        }

        cleanupLocationRequest()
        pendingLocationResult = result
        activeLocationManager = locationManager

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                val pendingResult = pendingLocationResult ?: return
                cleanupLocationRequest()
                pendingLocationResult = null
                pendingResult.success(locationToMap(location))
            }
        }

        activeLocationListener = listener

        try {
            for (provider in providers) {
                locationManager.requestLocationUpdates(
                    provider,
                    0L,
                    0f,
                    listener,
                    Looper.getMainLooper(),
                )
            }
        } catch (error: SecurityException) {
            cleanupLocationRequest()
            pendingLocationResult = null
            result.error("location_permission_denied", error.localizedMessage, null)
            return
        }

        val timeoutRunnable = Runnable {
            val pendingResult = pendingLocationResult ?: return@Runnable
            cleanupLocationRequest()
            pendingLocationResult = null
            pendingResult.error(
                "location_timeout",
                "Timed out while waiting for location.",
                null,
            )
        }
        locationTimeoutRunnable = timeoutRunnable
        mainHandler.postDelayed(timeoutRunnable, 12000)
    }

    private fun cleanupLocationRequest() {
        locationTimeoutRunnable?.let(mainHandler::removeCallbacks)
        locationTimeoutRunnable = null

        val manager = activeLocationManager
        val listener = activeLocationListener
        if (manager != null && listener != null) {
            runCatching { manager.removeUpdates(listener) }
        }

        activeLocationManager = null
        activeLocationListener = null
    }

    private fun locationToMap(location: Location): Map<String, Double> {
        return mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
        )
    }

    private fun handleOpenMapSearch(arguments: Any?, result: MethodChannel.Result) {
        val query = (arguments as? Map<*, *>)?.get("query") as? String
        if (query.isNullOrBlank()) {
            result.error("missing_query", "Search query is required.", null)
            return
        }

        val encodedQuery = Uri.encode(query)
        val intent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("geo:0,0?q=$encodedQuery"),
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        try {
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("map_open_failed", error.localizedMessage, null)
        }
    }

    private fun handleOpenDialer(arguments: Any?, result: MethodChannel.Result) {
        val phoneNumber = (arguments as? Map<*, *>)?.get("phone") as? String
        if (phoneNumber.isNullOrBlank()) {
            result.error("missing_phone", "Phone number is required.", null)
            return
        }

        val intent = Intent(
            Intent.ACTION_DIAL,
            Uri.parse("tel:$phoneNumber"),
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        try {
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("dialer_open_failed", error.localizedMessage, null)
        }
    }

    private fun handleOpenExternalUrl(arguments: Any?, result: MethodChannel.Result) {
        val url = (arguments as? Map<*, *>)?.get("url") as? String
        if (url.isNullOrBlank()) {
            result.error("missing_url", "URL is required.", null)
            return
        }

        val intent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse(url),
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        try {
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("url_open_failed", error.localizedMessage, null)
        }
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

        when (requestCode) {
            REQUEST_NOTIFICATION_PERMISSION -> {
                val result = pendingPermissionResult ?: return
                pendingPermissionResult = null
                val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
                result.success(granted)
            }
            REQUEST_LOCATION_PERMISSION -> {
                val result = pendingLocationResult ?: return
                val granted = grantResults.any { it == PackageManager.PERMISSION_GRANTED }
                if (granted) {
                    requestCurrentLocation()
                } else {
                    pendingLocationResult = null
                    result.error(
                        "location_permission_denied",
                        "Location permission was denied.",
                        null,
                    )
                }
            }
        }
    }

    private companion object {
        const val KEY_STATE_JSON = "state_json"
        const val KEY_SCHEDULED_NOTIFICATION_IDS = "scheduled_notification_ids"
        const val REQUEST_PICK_DOG_PHOTO = 1001
        const val REQUEST_NOTIFICATION_PERMISSION = 1002
        const val REQUEST_LOCATION_PERMISSION = 1003
    }
}
