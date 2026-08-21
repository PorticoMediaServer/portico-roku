# Portico for Roku

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
