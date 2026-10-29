/// The `neatedit` script ships inside the app. A sandboxed app can't put it
/// on the PATH itself, so it hands the user this command to run once.
public enum CommandLineTool {
    public static let linkPath = "/usr/local/bin/neatedit"

    public static func installCommand(script: String) -> String {
        "sudo mkdir -p /usr/local/bin && sudo ln -sf \(quoted(script)) \(linkPath)"
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
