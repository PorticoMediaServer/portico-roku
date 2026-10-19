<div align="center">
  <a href="https://getportico.tv">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/PorticoMediaServer/getportico-tv/main/public/brand/portico-wordmark-white.svg">
      <img src="https://raw.githubusercontent.com/PorticoMediaServer/getportico-tv/main/public/brand/portico-wordmark-black.svg" alt="Portico" width="420">
    </picture>
  </a>

  <h1>Portico for Roku</h1>

  <p><strong>The native Roku client for Portico Media Server.</strong></p>

  <p>
    <a href="https://github.com/PorticoMediaServer/portico-server">Portico Media Server</a> ·
    <a href="https://getportico.tv">Website</a> ·
    <a href="https://github.com/PorticoMediaServer/portico-roku/issues">Report an issue</a>
  </p>

  <p>
    <a href="LICENSE"><img alt="GPL-3.0-or-later" src="https://img.shields.io/badge/license-GPL--3.0--or--later-59636e?style=flat-square"></a>
    <img alt="Prerelease software" src="https://img.shields.io/badge/status-prerelease-e09f3e?style=flat-square">
  </p>
</div>

---

> Portico Media Server is the heart of the project. Start with the [primary `portico-server` repository](https://github.com/PorticoMediaServer/portico-server) or visit [getportico.tv](https://getportico.tv).

Portico for Roku is the native Roku client for browsing and playing media from Portico Media Server. It is prerelease software and is being published now so development can continue in the open.

## Technology

| Area | Technology |
| --- | --- |
| Roku application | SceneGraph and BrightScript |
| Source tooling | BrighterScript |
| Packaging | Sideloadable Roku channel ZIP |
| Validation | Node.js contract and behavior tests |
| Automation | GitHub Actions |

## Building

The repository includes the generated channel assets and golden test fixtures needed
for a standalone build. Install Node.js 24 and npm, then run:

```sh
npm ci
npm run check
npm test
npm run package
```

`npm test` compiles and runs the BrightScript logic tests against the committed
fixtures in an off-device interpreter. `npm run package` compiles the channel
with BrighterScript and writes `build/portico-roku.zip`, an **unsigned development
sideload ZIP**. These checks do not establish Roku hardware behavior, playback,
or Streaming Store certification.

### GitHub Actions artifacts

The CI workflow runs on pull requests, pushes to `main` and `roku-actions-builds`,
and manual dispatch. A successful run provides a `portico-roku-sideload` artifact
containing the compiled ZIP, its SHA-256 checksum, and build metadata identifying
the exact Roku commit and tool versions. The workflow checks the ZIP for expected
channel files and excludes authoring sources, tests, and dependencies. Download
and extract the Actions artifact to obtain `portico-roku.zip`.

This workflow does not create a signed `.pkg`. Roku requires a linked, online
Roku development device with the appropriate signing key to encrypt and sign
that package. See [Roku's packaging documentation](https://developer.roku.com/dev/docs/packaging-channels).
The workflow does not install on a device or publish to the Streaming Store.

### Updating generated assets and fixtures

Design tokens, strings, fonts, and settings are generated from Portico's shared
packages; layout constants are derived from the Apple TV app. To update these
inputs deliberately, clone compatible revisions of
[`portico-server`](https://github.com/PorticoMediaServer/portico-server) and
[`portico-react-native`](https://github.com/PorticoMediaServer/portico-react-native)
next to this repository, then run:

```sh
npm run generate
npm run fixtures:generate
npm run check
npm test
npm run package
```

Review and commit the generated changes together with their Roku adaptations.
The current generators reference upstream Apple literals and playback modules
that have since changed or been removed; they need migration before regeneration
against current sibling branches. Ordinary builds and tests use the checked-in
snapshot and do not read floating sibling branches.

## Support and warranty

Portico is provided **"AS IS", without warranty**, to the extent permitted by applicable law. Support is voluntary and not guaranteed, including responses, fixes, maintenance, and updates. See [SUPPORT.md](SUPPORT.md) and [LICENSE](LICENSE) for details.

## Feedback and contributions

Bug reports and product feedback are welcome through [GitHub Issues](https://github.com/PorticoMediaServer/portico-roku/issues). Portico does not accept external code contributions. See [CONTRIBUTING.md](CONTRIBUTING.md).

Please report security issues privately as described in [SECURITY.md](SECURITY.md).

## License and trademarks

This repository is licensed under `GPL-3.0-or-later`. See [LICENSE](LICENSE). The license does not permit unofficial builds to be represented as official Portico releases; see [TRADEMARKS.md](TRADEMARKS.md).

---

Made with ❤️ in Nova Scotia, Canada | Developed by [Justin Ehler](https://ehler.ca)  
Copyright © 2026 Justin Ehler  
Portico Media Server is free software licensed under the GNU General  
Public License, version 3 or, at your option, any later version.
