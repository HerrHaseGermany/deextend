import Foundation

enum L {
    /// Bundle matching follows macOS language order, including per-app overrides.
    /// English is the development-language fallback for unsupported languages.
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
