# Third-party components

MarkyQL's own code is MIT licensed (see `LICENSE`). It builds on, and at
build time downloads, the following third-party components. None of them is
GPL; MarkyQL is an independent implementation and contains no code from
QLMarkdown (GPL-3.0).

| Component | Version | License | How it is used |
| --- | --- | --- | --- |
| [cmark-gfm](https://github.com/github/cmark-gfm) | 0.29.0.gfm.13 (commit `587a12bb`) | MIT | Markdown parser, linked as a static library (git submodule) |
| [MathJax](https://www.mathjax.org) | 3.2.2 | Apache-2.0 | Renders TeX math in the preview (bundled at build time) |
| [Mermaid](https://mermaid.js.org) | 11.4.1 | MIT | Renders `mermaid` fenced blocks as diagrams (bundled at build time) |
| [highlight.js](https://highlightjs.org) | 11.9.0 | BSD-3-Clause | Syntax highlighting in the preview (bundled at build time) |
| [gemoji](https://github.com/github/gemoji) database | commit `fadaeaf1` | MIT | Emoji shortcode data (`emoji.json`, fetched at build time) |

`scripts/fetch-js.sh` downloads the JavaScript components and the emoji
database, verifying SHA-256 checksums for the versioned artifacts.
