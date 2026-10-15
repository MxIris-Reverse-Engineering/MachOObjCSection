// Single source of truth for the CLI version. Kept in step with the package's
// fork numbering (`<upstream major>.<upstream minor>.<P>NN`, P >= 1 following the upstream
// patch merged in: `0.8.111` before upstream 0.8.2, `0.8.200` after).
// When bumping: also add Changelogs/<value>.md, then tag the release with the same string.
// Verified by .github/workflows/version-check.yml (main) and .github/workflows/release.yml (tag),
// which publishes the universal binary to GitHub Releases.
enum BundledVersion {
    static let value = "0.8.200"
}
