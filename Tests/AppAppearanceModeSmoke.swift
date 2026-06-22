import Darwin
import SwiftUI

@main
struct AppAppearanceModeSmoke {
    static func main() {
        expect(AppAppearanceMode.storedValue("light").preferredColorScheme == .light, "light maps to light ColorScheme")
        expect(AppAppearanceMode.storedValue("dark").preferredColorScheme == .dark, "dark maps to dark ColorScheme")
        expect(AppAppearanceMode.storedValue("system").preferredColorScheme == nil, "system follows the OS ColorScheme")
        expect(AppAppearanceMode.storedValue("invalid") == .system, "unknown stored values fall back to system")
        expect(AppAccentPalette.storedValue("blue") == .blue, "known accent values are preserved")
        expect(AppAccentPalette.storedValue("invalid") == .green, "unknown accent values fall back to green")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
