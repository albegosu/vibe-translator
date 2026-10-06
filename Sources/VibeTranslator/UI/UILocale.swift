import Foundation

extension Locale {
    /// The language the interface is shown in (one of the app's localizations), so
    /// language names match the rest of the UI rather than the system region.
    static let ui = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "es")
}
