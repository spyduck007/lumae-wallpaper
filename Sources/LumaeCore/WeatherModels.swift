import Foundation

public enum WeatherTemperatureUnit: String, Codable, CaseIterable, Sendable {
    case celsius
    case fahrenheit
}

public enum WeatherLocationMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case manual
}

public enum WeatherWidgetMode: String, Codable, CaseIterable, Sendable {
    case current
    case forecast
}
