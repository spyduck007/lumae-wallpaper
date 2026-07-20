import AppKit
import Combine
import CoreLocation
import Foundation
import LumaeCore

struct WeatherDayForecast: Equatable, Identifiable {
    var id: Date { date }
    var date: Date
    var highCelsius: Double
    var lowCelsius: Double
    var condition: WeatherCondition

    func high(in unit: WeatherTemperatureUnit) -> Double {
        WeatherSnapshot.convert(highCelsius, to: unit)
    }

    func low(in unit: WeatherTemperatureUnit) -> Double {
        WeatherSnapshot.convert(lowCelsius, to: unit)
    }
}

struct WeatherSnapshot: Equatable {
    var temperatureCelsius: Double?
    var highCelsius: Double?
    var lowCelsius: Double?
    var condition: WeatherCondition
    var isDaytime: Bool
    var locationName: String
    var updatedAt: Date
    var errorMessage: String?
    /// Upcoming days after today, used by the "forecast" widget layout.
    var upcomingDays: [WeatherDayForecast] = []

    static let empty = WeatherSnapshot(
        temperatureCelsius: nil,
        highCelsius: nil,
        lowCelsius: nil,
        condition: .unknown,
        isDaytime: true,
        locationName: "",
        updatedAt: .distantPast,
        errorMessage: nil
    )

    var symbolName: String { condition.symbolName(isDay: isDaytime) }

    var hasData: Bool { temperatureCelsius != nil }

    func temperature(in unit: WeatherTemperatureUnit) -> Double? {
        temperatureCelsius.map { Self.convert($0, to: unit) }
    }

    func high(in unit: WeatherTemperatureUnit) -> Double? {
        highCelsius.map { Self.convert($0, to: unit) }
    }

    func low(in unit: WeatherTemperatureUnit) -> Double? {
        lowCelsius.map { Self.convert($0, to: unit) }
    }

    static func convert(_ celsius: Double, to unit: WeatherTemperatureUnit) -> Double {
        unit == .celsius ? celsius : celsius * 9 / 5 + 32
    }
}

enum WeatherCondition: Equatable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case rain
    case freezingRain
    case snow
    case thunderstorm
    case unknown

    var label: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly Cloudy"
        case .cloudy: return "Cloudy"
        case .fog: return "Foggy"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .freezingRain: return "Freezing Rain"
        case .snow: return "Snow"
        case .thunderstorm: return "Thunderstorms"
        case .unknown: return "—"
        }
    }

    func symbolName(isDay: Bool) -> String {
        switch self {
        case .clear: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .freezingRain: return "cloud.sleet.fill"
        case .snow: return "cloud.snow.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Maps Open-Meteo's WMO weather codes to a small display-friendly set.
    /// https://open-meteo.com/en/docs
    static func fromWMOCode(_ code: Int) -> WeatherCondition {
        switch code {
        case 0: return .clear
        case 1, 2: return .partlyCloudy
        case 3: return .cloudy
        case 45, 48: return .fog
        case 51, 53, 55, 56, 57: return .drizzle
        case 61, 63, 65, 80, 81, 82: return .rain
        case 66, 67: return .freezingRain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .thunderstorm
        default: return .unknown
        }
    }
}

/// Fetches current weather from Open-Meteo (open-meteo.com) — chosen
/// specifically because it needs no account and no API key, matching
/// Lumae's "no accounts, no tracking" stance even though this is the one
/// feature that requires a network request. Location comes from
/// CoreLocation (automatic) or CLGeocoder resolving a user-entered place
/// name (manual); both are Apple's own services, not third parties.
@MainActor
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherService()

    @Published private(set) var snapshot = WeatherSnapshot.empty

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let session = URLSession(configuration: .ephemeral)

    private var activeObserverCount = 0
    private var timer: Timer?
    private var fetchTask: Task<Void, Never>?

    private var isEnabled = false
    private var locationMode: WeatherLocationMode = .automatic
    private var manualLocationName = ""
    private var resolvedManualLocation: (name: String, coordinate: CLLocationCoordinate2D)?

    private static let refreshInterval: TimeInterval = 1800

    private override init() {
        super.init()
        locationManager.delegate = self
    }

    /// Widgets call this while a Weather widget is actually on screen
    /// (editor preview or live desktop overlay), the same reference-counted
    /// pattern used by NowPlayingService/BatteryService, so polling and
    /// location tracking only run while something needs them.
    func beginObserving() {
        activeObserverCount += 1
        guard timer == nil else { return }
        startPollingIfNeeded()
    }

    func endObserving() {
        activeObserverCount = max(0, activeObserverCount - 1)
        guard activeObserverCount == 0 else { return }
        timer?.invalidate()
        timer = nil
        fetchTask?.cancel()
        fetchTask = nil
    }

    /// Pushed from AppModel whenever the relevant Settings change. Weather
    /// widgets have no access to AppModel themselves (they're hosted
    /// directly via AppKit outside the normal SwiftUI environment, the
    /// same reason NowPlayingService/BatteryService are self-contained
    /// singletons), so this is how global location/opt-in state reaches
    /// the service that actually renders on the desktop.
    func updateConfiguration(
        enabled: Bool,
        locationMode: WeatherLocationMode,
        manualLocationName: String
    ) {
        let locationChanged = self.locationMode != locationMode
            || self.manualLocationName != manualLocationName
        let becameEnabled = enabled && !isEnabled

        isEnabled = enabled
        self.locationMode = locationMode
        self.manualLocationName = manualLocationName

        guard enabled else {
            fetchTask?.cancel()
            snapshot = .empty
            return
        }

        if locationChanged {
            resolvedManualLocation = nil
        }

        if activeObserverCount > 0 {
            startPollingIfNeeded()
            if becameEnabled || locationChanged {
                refresh()
            }
        }
    }

    private func startPollingIfNeeded() {
        guard isEnabled else { return }
        if isEnabled, locationMode == .automatic {
            locationManager.requestWhenInUseAuthorization()
        }
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard isEnabled else { return }
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            await self?.performRefresh()
        }
    }

    private func performRefresh() async {
        do {
            let (coordinate, name) = try await resolveLocation()
            guard !Task.isCancelled else { return }
            let result = try await fetchWeather(at: coordinate)
            guard !Task.isCancelled else { return }
            snapshot = WeatherSnapshot(
                temperatureCelsius: result.temperatureCelsius,
                highCelsius: result.highCelsius,
                lowCelsius: result.lowCelsius,
                condition: result.condition,
                isDaytime: result.isDaytime,
                locationName: name,
                updatedAt: Date(),
                errorMessage: nil,
                upcomingDays: result.upcomingDays
            )
        } catch is CancellationError {
            // Superseded by a newer refresh; leave the existing snapshot.
        } catch {
            guard !Task.isCancelled else { return }
            snapshot.errorMessage = (error as? WeatherServiceError)?.message
                ?? error.localizedDescription
        }
    }

    private func resolveLocation() async throws -> (CLLocationCoordinate2D, String) {
        switch locationMode {
        case .automatic:
            let location = try await currentLocation()
            let name = await reverseGeocodedName(for: location) ?? "Current Location"
            return (location.coordinate, name)

        case .manual:
            let trimmed = manualLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw WeatherServiceError.noManualLocation
            }
            if let resolved = resolvedManualLocation, resolved.name == trimmed {
                return (resolved.coordinate, trimmed)
            }
            let placemarks = try await geocoder.geocodeAddressString(trimmed)
            guard let coordinate = placemarks.first?.location?.coordinate else {
                throw WeatherServiceError.locationNotFound
            }
            resolvedManualLocation = (trimmed, coordinate)
            return (coordinate, trimmed)
        }
    }

    private func currentLocation() async throws -> CLLocation {
        let status = locationManager.authorizationStatus
        guard status == .authorized || status == .authorizedAlways else {
            throw WeatherServiceError.locationPermissionDenied
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingLocationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    private var pendingLocationContinuation: CheckedContinuation<CLLocation, Error>?

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.pendingLocationContinuation?.resume(returning: location)
            self.pendingLocationContinuation = nil
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.pendingLocationContinuation?.resume(throwing: error)
            self.pendingLocationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        Task { @MainActor in
            guard self.isEnabled, self.locationMode == .automatic,
                  self.activeObserverCount > 0 else { return }
            self.refresh()
        }
    }

    private func reverseGeocodedName(for location: CLLocation) async -> String? {
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return nil
        }
        return placemark.locality ?? placemark.name
    }

    private func fetchWeather(
        at coordinate: CLLocationCoordinate2D
    ) async throws -> (
        temperatureCelsius: Double,
        highCelsius: Double,
        lowCelsius: Double,
        condition: WeatherCondition,
        isDaytime: Bool,
        upcomingDays: [WeatherDayForecast]
    ) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            // Today plus five upcoming days, for the "forecast" widget layout.
            URLQueryItem(name: "forecast_days", value: "6"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else {
            throw WeatherServiceError.invalidRequest
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw WeatherServiceError.requestFailed
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: decoded.timezone ?? "UTC") ?? .current

        let dayCount = min(
            decoded.daily.time.count,
            decoded.daily.weatherCode.count,
            decoded.daily.temperature2mMax.count,
            decoded.daily.temperature2mMin.count
        )
        // Index 0 is today, already represented by `current`; the strip
        // shows the days after it.
        let upcomingDays: [WeatherDayForecast] = (1..<max(dayCount, 1)).compactMap { index in
            guard let date = dateFormatter.date(from: decoded.daily.time[index]) else {
                return nil
            }
            return WeatherDayForecast(
                date: date,
                highCelsius: decoded.daily.temperature2mMax[index],
                lowCelsius: decoded.daily.temperature2mMin[index],
                condition: WeatherCondition.fromWMOCode(decoded.daily.weatherCode[index])
            )
        }

        return (
            decoded.current.temperature2m,
            decoded.daily.temperature2mMax.first ?? decoded.current.temperature2m,
            decoded.daily.temperature2mMin.first ?? decoded.current.temperature2m,
            WeatherCondition.fromWMOCode(decoded.current.weatherCode),
            decoded.current.isDay != 0,
            upcomingDays
        )
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature2m: Double
        let weatherCode: Int
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    struct Daily: Decodable {
        let time: [String]
        let weatherCode: [Int]
        let temperature2mMax: [Double]
        let temperature2mMin: [Double]

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
        }
    }

    let current: Current
    let daily: Daily
    let timezone: String?
}

enum WeatherServiceError: LocalizedError {
    case locationPermissionDenied
    case locationNotFound
    case noManualLocation
    case invalidRequest
    case requestFailed

    var message: String {
        switch self {
        case .locationPermissionDenied:
            return "Location access is needed for automatic weather."
        case .locationNotFound:
            return "Couldn't find that location."
        case .noManualLocation:
            return "Set a location in Settings."
        case .invalidRequest, .requestFailed:
            return "Weather is temporarily unavailable."
        }
    }

    var errorDescription: String? { message }
}
