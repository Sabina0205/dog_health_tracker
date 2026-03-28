import Flutter
import CoreLocation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
  private var locationManager: CLLocationManager?
  private var pendingLocationResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let externalChannel = FlutterMethodChannel(
        name: "pet_health/external",
        binaryMessenger: controller.binaryMessenger
      )

      externalChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "getCurrentLocation":
          self.handleGetCurrentLocation(result: result)

        case "openMapSearch":
          guard
            let args = call.arguments as? [String: Any],
            let query = args["query"] as? String,
            !query.isEmpty
          else {
            result(
              FlutterError(
                code: "missing_query",
                message: "Search query is required.",
                details: nil
              )
            )
            return
          }

          let encodedQuery = query.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
          ) ?? query

          guard let url = URL(string: "http://maps.apple.com/?q=\(encodedQuery)") else {
            result(
              FlutterError(
                code: "invalid_url",
                message: "Unable to build maps URL.",
                details: nil
              )
            )
            return
          }

          UIApplication.shared.open(url, options: [:]) { success in
            if success {
              result(nil)
            } else {
              result(
                FlutterError(
                  code: "map_open_failed",
                  message: "Unable to open Maps.",
                  details: nil
                )
              )
            }
          }

        case "openExternalUrl":
          guard
            let args = call.arguments as? [String: Any],
            let urlString = args["url"] as? String,
            let url = URL(string: urlString)
          else {
            result(
              FlutterError(
                code: "missing_url",
                message: "URL is required.",
                details: nil
              )
            )
            return
          }

          UIApplication.shared.open(url, options: [:]) { success in
            if success {
              result(nil)
            } else {
              result(
                FlutterError(
                  code: "url_open_failed",
                  message: "Unable to open URL.",
                  details: nil
                )
              )
            }
          }

        case "openDialer":
          guard
            let args = call.arguments as? [String: Any],
            let phone = args["phone"] as? String,
            !phone.isEmpty
          else {
            result(
              FlutterError(
                code: "missing_phone",
                message: "Phone number is required.",
                details: nil
              )
            )
            return
          }

          guard let url = URL(string: "tel://\(phone)") else {
            result(
              FlutterError(
                code: "invalid_phone",
                message: "Unable to build phone URL.",
                details: nil
              )
            )
            return
          }

          UIApplication.shared.open(url, options: [:]) { success in
            if success {
              result(nil)
            } else {
              result(
                FlutterError(
                  code: "dialer_open_failed",
                  message: "Unable to open Phone.",
                  details: nil
                )
              )
            }
          }

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleGetCurrentLocation(result: @escaping FlutterResult) {
    guard CLLocationManager.locationServicesEnabled() else {
      result(
        FlutterError(
          code: "location_services_disabled",
          message: "Location services are disabled.",
          details: nil
        )
      )
      return
    }

    if pendingLocationResult != nil {
      result(
        FlutterError(
          code: "location_request_in_progress",
          message: "Location request is already in progress.",
          details: nil
        )
      )
      return
    }

    pendingLocationResult = result

    let manager = locationManager ?? CLLocationManager()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    locationManager = manager

    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .restricted, .denied:
      pendingLocationResult = nil
      result(
        FlutterError(
          code: "location_permission_denied",
          message: "Location permission was denied.",
          details: nil
        )
      )
    @unknown default:
      pendingLocationResult = nil
      result(
        FlutterError(
          code: "location_unknown",
          message: "Unknown location permission state.",
          details: nil
        )
      )
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard let result = pendingLocationResult else {
      return
    }

    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .restricted, .denied:
      pendingLocationResult = nil
      result(
        FlutterError(
          code: "location_permission_denied",
          message: "Location permission was denied.",
          details: nil
        )
      )
    case .notDetermined:
      break
    @unknown default:
      pendingLocationResult = nil
      result(
        FlutterError(
          code: "location_unknown",
          message: "Unknown location permission state.",
          details: nil
        )
      )
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let result = pendingLocationResult, let location = locations.last else {
      return
    }

    pendingLocationResult = nil
    result([
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
    ])
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    guard let result = pendingLocationResult else {
      return
    }

    pendingLocationResult = nil
    result(
      FlutterError(
        code: "location_failed",
        message: error.localizedDescription,
        details: nil
      )
    )
  }
}
