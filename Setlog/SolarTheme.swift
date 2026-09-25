import Foundation
import CoreLocation
import Combine

enum AppearanceMode: String {
    case device
    case sun
}

@MainActor
final class SolarTheme: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var dark: Bool?
    @Published private(set) var label = "Following iPhone"
    @Published private(set) var mode: AppearanceMode

    private let manager = CLLocationManager()
    private var coordinate: CLLocationCoordinate2D?

    override init() {
        mode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "setlog-appearance-mode") ?? "") ?? .device
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if mode == .sun && (manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse) {
            manager.requestLocation()
        }
    }

    func setMode(_ newMode: AppearanceMode) {
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: "setlog-appearance-mode")
        if newMode == .device {
            dark = nil
            label = "Following iPhone"
        } else {
            requestLocation()
        }
    }

    func requestLocation() {
        guard mode == .sun else { return }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { manager.requestLocation() }
        else { dark = nil; label = "Location unavailable" }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.mode == .sun && (self.manager.authorizationStatus == .authorizedAlways || self.manager.authorizationStatus == .authorizedWhenInUse) {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let latitude = latest.coordinate.latitude
        let longitude = latest.coordinate.longitude
        Task { @MainActor [weak self] in
            guard self?.mode == .sun else { return }
            self?.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            self?.update()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard self?.mode == .sun else { return }
            self?.dark = nil
            self?.label = "Location unavailable"
        }
    }

    func update() {
        guard mode == .sun else { dark = nil; label = "Following iPhone"; return }
        guard let coordinate,
              let sunrise = solarEvent(date: Date(), coordinate: coordinate, rising: true),
              let sunset = solarEvent(date: Date(), coordinate: coordinate, rising: false) else { return }
        let now = Date()
        dark = now < sunrise || now >= sunset
        let next = now < sunrise ? sunrise : (now < sunset ? sunset : solarEvent(date: now.addingTimeInterval(86_400), coordinate: coordinate, rising: true))
        if let next {
            label = "\(dark == true ? "Sunrise" : "Sunset") \(next.formatted(date: .omitted, time: .shortened))"
        }
    }

    private func solarEvent(date: Date, coordinate: CLLocationCoordinate2D, rising: Bool) -> Date? {
        let calendar = Calendar(identifier: .gregorian)
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let longitudeHour = coordinate.longitude / 15
        let estimate = day + ((rising ? 6 : 18) - longitudeHour) / 24
        let meanAnomaly = 0.9856 * estimate - 3.289
        let trueLongitude = normalized(meanAnomaly + 1.916 * sin(rad(meanAnomaly)) + 0.020 * sin(2 * rad(meanAnomaly)) + 282.634)
        var rightAscension = normalized(deg(atan(0.91764 * tan(rad(trueLongitude)))))
        rightAscension += floor(trueLongitude / 90) * 90 - floor(rightAscension / 90) * 90
        rightAscension /= 15
        let sinDec = 0.39782 * sin(rad(trueLongitude))
        let cosDec = cos(asin(sinDec))
        let cosineHour = (cos(rad(90.833)) - sinDec * sin(rad(coordinate.latitude))) / (cosDec * cos(rad(coordinate.latitude)))
        guard (-1...1).contains(cosineHour) else { return nil }
        let hourAngle = (rising ? 360 - deg(acos(cosineHour)) : deg(acos(cosineHour))) / 15
        let localMean = hourAngle + rightAscension - 0.06571 * estimate - 6.622
        let utcHour = localMean - longitudeHour
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let localComponents = calendar.dateComponents([.year, .month, .day], from: date)
        guard let midnight = utc.date(from: localComponents) else { return nil }
        return midnight.addingTimeInterval(utcHour * 3600)
    }

    private func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private func deg(_ radians: Double) -> Double { radians * 180 / .pi }
    private func normalized(_ value: Double) -> Double { (value.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
}
