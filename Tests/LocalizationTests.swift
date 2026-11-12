import Foundation

@main
struct LocalizationTests {
    static func main() {
        let expected = CommandLine.arguments.last!
        let connect = L.text("action.connect")
        precondition(connect == (expected == "de" ? "Verbinden" : "Connect"), "Wrong localization: \(connect)")
        precondition(L.text("notice.body", "Test Monitor").contains("Test Monitor"))
        precondition(!L.text("error.operation", "Test", Int32(42)).contains("%@"))
        print("PASS: \(expected) bundle language matching and formatted messages")
    }
}
