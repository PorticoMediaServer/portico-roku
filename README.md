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
| Packaging | Deterministic Roku channel ZIP |
| Validation | Node.js contract and behavior tests |
| Automation | GitHub Actions |

## Building

Install Node.js and npm, then run:

```sh
npm ci
npm run compile
npm run package:release
```

The resulting channel package is intended for development sideloading. Roku Channel Store publication will happen separately when the client is ready.

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
