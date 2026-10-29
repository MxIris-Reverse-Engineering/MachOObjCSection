// The CLI's version string, frozen at 0.8.204: the last release that published a
// prebuilt binary. objc-section has moved into MachOSwiftSection as `swift-section objc`
// and is no longer released, so the package's later versions are git tags alone and do
// not touch this file (the release section of Documentations/README.md). It goes with
// the CLI (evolution proposal `remove-objc-section-cli`).
enum BundledVersion {
    static let value = "0.8.204"
}
