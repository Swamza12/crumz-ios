import Foundation
import CoreLocation
import MapKit
import Combine

// MARK: - Route Service (Matches InAppNavigation.kt + Native MKDirections Fallback)
enum RouteService {
    static var lastNavError: String?

    /// Computes a walking or driving route from `origin` to `dest`.
    /// 1. First attempts Google Routes API v2 (`https://routes.googleapis.com/directions/v2:computeRoutes`)
    ///    matching Android's `fetchRoute` 1:1.
    /// 2. Automatically falls back to Apple `MKDirections` if Google's API key is restricted to Android SHA-1,
    ///    guaranteeing reliable turn-by-turn routes on every iPhone.
    static func fetchRoute(
        origin: CLLocationCoordinate2D,
        dest: CLLocationCoordinate2D,
        mode: String,
        apiKey: String
    ) async -> NavRoute? {
        if !apiKey.isEmpty, let googleRoute = await fetchGoogleRoute(origin: origin, dest: dest, mode: mode, apiKey: apiKey) {
            return googleRoute
        }
        return await fetchAppleMapKitRoute(origin: origin, dest: dest, mode: mode)
    }

    private static func fetchGoogleRoute(
        origin: CLLocationCoordinate2D,
        dest: CLLocationCoordinate2D,
        mode: String,
        apiKey: String
    ) async -> NavRoute? {
        guard let url = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes") else {
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline," +
            "routes.legs.steps.navigationInstruction,routes.legs.steps.distanceMeters,routes.legs.steps.endLocation",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        if let bundleId = Bundle.main.bundleIdentifier {
            request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }

        let payload: [String: Any] = [
            "origin": [
                "location": [
                    "latLng": ["latitude": origin.latitude, "longitude": origin.longitude]
                ]
            ],
            "destination": [
                "location": [
                    "latLng": ["latitude": dest.latitude, "longitude": dest.longitude]
                ]
            ],
            "travelMode": mode == "walking" ? "WALK" : "DRIVE",
            "units": "METRIC",
            "languageCode": "en-US"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            if let errorDict = json["error"] as? [String: Any] {
                lastNavError = errorDict["message"] as? String ?? "Routes API error"
                return nil
            }

            guard let routes = json["routes"] as? [[String: Any]], let route = routes.first else {
                lastNavError = "No route found"
                return nil
            }

            var steps: [NavStep] = []
            if let legs = route["legs"] as? [[String: Any]],
               let firstLeg = legs.first,
               let stepsJson = firstLeg["steps"] as? [[String: Any]] {
                for s in stepsJson {
                    let endLoc = (s["endLocation"] as? [String: Any])?["latLng"] as? [String: Any]
                    let endLat = endLoc?["latitude"] as? Double ?? dest.latitude
                    let endLng = endLoc?["longitude"] as? Double ?? dest.longitude
                    let nav = s["navigationInstruction"] as? [String: Any]
                    let rawInstr = (nav?["instructions"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let maneuver = nav?["maneuver"] as? String ?? ""
                    let distMeters = s["distanceMeters"] as? Int ?? 0

                    steps.append(
                        NavStep(
                            instruction: rawInstr.isEmpty ? "Continue" : rawInstr,
                            maneuver: maneuver,
                            distanceText: formatMeters(distMeters),
                            end: CLLocationCoordinate2D(latitude: endLat, longitude: endLng)
                        )
                    )
                }
            }

            let durationStr = (route["duration"] as? String ?? "0s").replacingOccurrences(of: "s", with: "")
            let seconds = Double(durationStr) ?? 0.0
            let mins = max(1, Int((seconds / 60.0).rounded()))
            let totalMeters = route["distanceMeters"] as? Int ?? 0
            let encodedPoly = (route["polyline"] as? [String: Any])?["encodedPolyline"] as? String ?? ""
            let points = decodePolyline(encodedPoly)

            guard !points.isEmpty else { return nil }

            return NavRoute(
                points: points,
                steps: steps,
                distanceText: formatMeters(totalMeters),
                durationText: "\(mins) min"
            )
        } catch {
            lastNavError = error.localizedDescription
            return nil
        }
    }

    private static func fetchAppleMapKitRoute(
        origin: CLLocationCoordinate2D,
        dest: CLLocationCoordinate2D,
        mode: String
    ) async -> NavRoute? {
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
        req.transportType = (mode == "walking") ? .walking : .automobile
        req.requestsAlternateRoutes = false

        let directions = MKDirections(request: req)
        do {
            let response = try await directions.calculate()
            guard let mkRoute = response.routes.first else {
                lastNavError = "No route found"
                return nil
            }

            let count = mkRoute.polyline.pointCount
            var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: count)
            mkRoute.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))

            let steps: [NavStep] = mkRoute.steps.compactMap { s in
                let stepCount = s.polyline.pointCount
                guard stepCount > 0 else { return nil }
                var stepCoords = Array(repeating: kCLLocationCoordinate2DInvalid, count: stepCount)
                s.polyline.getCoordinates(&stepCoords, range: NSRange(location: 0, length: stepCount))
                let endCoord = stepCoords.last ?? dest
                let instr = s.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                if instr.isEmpty && s.distance < 1 { return nil }
                return NavStep(
                    instruction: instr.isEmpty ? "Continue toward destination" : instr,
                    maneuver: "",
                    distanceText: formatMeters(Int(s.distance.rounded())),
                    end: endCoord
                )
            }

            let mins = max(1, Int((mkRoute.expectedTravelTime / 60.0).rounded()))
            return NavRoute(
                points: coords,
                steps: steps,
                distanceText: formatMeters(Int(mkRoute.distance.rounded())),
                durationText: "\(mins) min"
            )
        } catch {
            lastNavError = error.localizedDescription
            return nil
        }
    }

    static func formatMeters(_ m: Int) -> String {
        if m >= 1000 {
            return String(format: "%.1f km", Double(m) / 1000.0)
        } else {
            return "\(m) m"
        }
    }

    /// Google Encoded Polyline Decoder (Matches InAppNavigation.kt `decodePolyline` 1:1)
    static func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        var poly: [CLLocationCoordinate2D] = []
        let bytes = Array(encoded.utf8)
        var index = 0
        var lat = 0
        var lng = 0

        while index < bytes.count {
            var shift = 0
            var result = 0
            var b: Int
            repeat {
                guard index < bytes.count else { return poly }
                b = Int(bytes[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
            } while b >= 0x20
            let dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1)
            lat += dlat

            shift = 0
            result = 0
            repeat {
                guard index < bytes.count else { return poly }
                b = Int(bytes[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
            } while b >= 0x20
            let dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1)
            lng += dlng

            poly.append(
                CLLocationCoordinate2D(
                    latitude: Double(lat) / 1e5,
                    longitude: Double(lng) / 1e5
                )
            )
        }
        return poly
    }
}

// MARK: - Live GPS + Smoothed Compass Heading Manager
final class LocationHeadingManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var userLocation: CLLocation?
    @Published var compassHeading: Double?
    @Published var hasLocationPermission: Bool = false

    private let manager = CLLocationManager()
    private var onPermissionGrantedCallback: (() -> Void)?
    private var onPermissionDeniedCallback: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 2.0
        manager.headingFilter = 2.0
        refreshAuthorizationState()
    }

    func refreshAuthorizationState() {
        let status = manager.authorizationStatus
        let granted = (status == .authorizedWhenInUse || status == .authorizedAlways)
        hasLocationPermission = granted
        if granted {
            manager.startUpdatingLocation()
        }
    }

    func requestPermission(onGranted: @escaping () -> Void, onDenied: @escaping () -> Void) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            hasLocationPermission = true
            manager.startUpdatingLocation()
            onGranted()
        } else if status == .notDetermined {
            onPermissionGrantedCallback = onGranted
            onPermissionDeniedCallback = onDenied
            manager.requestWhenInUseAuthorization()
        } else {
            hasLocationPermission = false
            onDenied()
        }
    }

    func setHeadingUpdates(active: Bool) {
        guard CLLocationManager.headingAvailable() else { return }
        if active {
            manager.startUpdatingHeading()
        } else {
            manager.stopUpdatingHeading()
        }
    }

    func stopAll() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let granted = (status == .authorizedWhenInUse || status == .authorizedAlways)
        DispatchQueue.main.async {
            self.hasLocationPermission = granted
            if granted {
                manager.startUpdatingLocation()
                self.onPermissionGrantedCallback?()
            } else if status == .denied || status == .restricted {
                self.onPermissionDeniedCallback?()
            }
            self.onPermissionGrantedCallback = nil
            self.onPermissionDeniedCallback = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        DispatchQueue.main.async {
            self.userLocation = latest
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let raw = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard raw >= 0 else { return }
        let az = (raw.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)

        DispatchQueue.main.async {
            if let prev = self.compassHeading {
                var diff = az - prev
                if diff > 180 { diff -= 360 }
                if diff < -180 { diff += 360 }
                self.compassHeading = (prev + diff * 0.15 + 360).truncatingRemainder(dividingBy: 360)
            } else {
                self.compassHeading = az
            }
        }
    }

    static func distanceMeters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB)
    }

    static func bearingDegrees(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180.0
        let lon1 = a.longitude * .pi / 180.0
        let lat2 = b.latitude * .pi / 180.0
        let lon2 = b.longitude * .pi / 180.0
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let brng = atan2(y, x) * 180.0 / .pi
        return (brng + 360.0).truncatingRemainder(dividingBy: 360.0)
    }
}
