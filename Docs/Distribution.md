# Arklike Distribution Notes

## Distribution Route

Arklike is distributed as a direct-download macOS app through GitHub Releases, then installed by Homebrew as a Cask from the tools tap.

The release artifact is a `zip` containing `Arklike.app`. The app is signed with a Developer ID Application certificate, uses the hardened runtime, is notarized by Apple, and is stapled before packaging.

## Release Flow

The project uses `.github/workflows/release.yml`.

### Automatic releases from `main`

On pushes to `main`, `release-please` checks conventional commits and opens or updates a release PR. When that PR is merged, the workflow:

1. Updates `Arklike/Info.plist` through release-please.
2. Creates a GitHub Release and tag.
3. Builds `Arklike.app` on a macOS runner.
4. Imports the Developer ID certificate with `apple-actions/import-codesign-certs`.
5. Signs, notarizes, staples, and validates the app with Apple's `codesign`, `notarytool`, and `stapler`.
6. Zips the app and calculates SHA256.
7. Uploads `Arklike-<version>.zip` and its `.sha256` file to the release.
8. Updates the Homebrew cask in the tools tap when tap secrets are configured.

Use conventional commits for versioning:

```sh
git commit -m "feat: add profile picker"
git commit -m "fix: handle empty Safari windows"
git commit -m "feat!: change shortcut storage format"
```

### Manual tag releases

You can also create a release by pushing a tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The same workflow will build, sign, notarize, create or update the GitHub Release, and update the tap.

## Required GitHub Secrets

Configure these in the Arklike repository settings:

- `MACOS_CERTIFICATE_P12`: Base64-encoded Developer ID Application `.p12` certificate.
- `MACOS_CERTIFICATE_PASSWORD`: Password for the `.p12` file.
- `APPLE_ID`: Apple ID email used for notarization.
- `APPLE_TEAM_ID`: Apple Developer Team ID.
- `APPLE_APP_SPECIFIC_PASSWORD`: App-specific password for notarization.

Optional:

- `RELEASE_PLEASE_TOKEN`: A fine-grained PAT with repo contents and pull request access. If omitted, `GITHUB_TOKEN` is used.

## Homebrew Tap Secrets and Variables

To update your tools tap automatically, configure these in the Arklike repository:

Secrets:

- `TAP_REPOSITORY`: Tap repository in `owner/repo` form, for example `CarterMcAlister/homebrew-tools`.
- `TAP_REPO_PAT`: PAT with write access to the tap repository.

Variables:

- `TAP_CASK_PATH`: Optional. Defaults to `Casks/arklike.rb`.
- `TAP_CASK_TOKEN`: Optional. Defaults to `arklike`.

The generated cask downloads from:

```ruby
url "https://github.com/CarterMcAlister/arklike/releases/download/v#{version}/Arklike-#{version}.zip"
```

## Creating the Signing Secret

Export a Developer ID Application certificate from Keychain Access as a `.p12`, then encode it:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Paste the copied value into `MACOS_CERTIFICATE_P12`.

The workflow imports this certificate with `apple-actions/import-codesign-certs@v6`, signs with hardened runtime, submits the app to Apple's notary service with `notarytool`, and staples the notarization ticket before creating the release zip.

## Sandbox Posture

The MVP remains unsandboxed. Safari Apple Events, Accessibility-driven shortcut capture, System Events menu automation, and default-browser routing are core requirements and should be proven before revisiting App Store constraints.

## First-Run Onboarding

The first-run experience should guide users through:

1. Accessibility permission for Safari shortcut interception, active-window tracking, profile menu automation, and sidebar toggling.
2. Apple Events permission for Safari tab/window automation and URL copying.
3. Optional default-browser setup for Traffic Control external link routing.
4. Safari profile setup, including manual profile names when discovery fails.

## Future Updates

If distributing directly outside Homebrew, add Sparkle or an equivalent updater after the MVP is stable.
