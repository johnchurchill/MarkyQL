# MarkyQL

A macOS Quick Look extension for Markdown files, written in Objective-C.

Select a `.md` file in Finder, press Space, read it — fully rendered:
GitHub-flavored Markdown, syntax highlighting, tables, task lists,
alerts, definition lists, emoji, Mermaid diagrams, and (only if you
ask for it) math formulas.

**MarkyQL adds nothing to your previews.** No banners, no counters, no
donation links, no "you have viewed N files" messages — not every 100
files, not ever. What you see is your document.

MarkyQL is an independent, from-scratch implementation. It contains no
code from QLMarkdown (GPL-3.0); see `THIRD-PARTY.md` for the components
it does use (all MIT / Apache-2.0 / BSD).

## Features

Everything below is a **real toggle** in the settings app. Turning a
feature off removes both its markup and its JavaScript from the output.

- cmark-gfm core: tables, strikethrough, autolink, tag filter, task lists, footnotes
- GitHub alerts (`[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`)
- Definition lists, heading anchors, table of contents
- `==highlight==`, `~sub~` / `^sup^` scripts, `[[wikilinks]]`, `:emoji:` shortcodes
- Syntax highlighting (highlight.js, GitHub themes, light + dark)
- Mermaid diagrams from ` ```mermaid ` fenced blocks; bare `.mermaid` files render as diagrams
- YAML front matter rendered as a table
- Local images inlined as data URIs (the Quick Look sandbox can't read them otherwise)
- Themes: bundled GitHub-style CSS, or your own CSS file
- File types: `.md`, `.markdown`, `.mdown`, `.rmd`, `.mdx`, `.mdc`, `.qmd`, `.apib`,
  `.mermaid`, and textbundle packages
- A `markyql` command-line tool that renders the same HTML the extension shows

**Math is off by default.** MathJax is a big payload and `$` detection
misfires on ordinary prose with prices in it. With Math off, MathJax is
never loaded and `$` is never treated specially. Turn it on in the
settings app only if your documents actually contain TeX.

## Requirements

- macOS 12 or later
- Xcode Command Line Tools (`xcode-select --install`)
- `cmake` (`brew install cmake`)
- Network access for the first build (fetches the parser and the
  pinned JavaScript dependencies)

## Build

```sh
git clone --recurse-submodules https://github.com/johnchurchill/MarkyQL.git
cd MarkyQL
make
```

`make` builds cmark-gfm (universal arm64 + x86_64 static libraries),
downloads and checksum-verifies MathJax, Mermaid, highlight.js and the
gemoji database via `scripts/fetch-js.sh`, compiles the Objective-C
sources, assembles `build/MarkyQL.app` with the Quick Look extension
inside it, and ad-hoc signs the bundle.

No Xcode project, no IDE: the whole build is the `Makefile`.

## Install

```sh
make install
```

This copies the app to `/Applications`, launches it once (which is
what registers the Quick Look extension with the system), and resets
the Quick Look cache. The settings window opens on that first launch;
close it and you're done.

Then select any `.md` file in Finder and press Space.

If the preview doesn't appear, check that the extension is enabled in
**System Settings → General → Login Items & Extensions → Quick Look**,
and make sure no other Markdown Quick Look extension is winning —
only one extension handles a given file type. (If QLMarkdown is
installed, disable it there; you can keep both apps installed.)

To uninstall: `make uninstall`, or drag `/Applications/MarkyQL.app`
to the Trash. Settings live in
`~/Library/Group Containers/group.com.markyql.shared` and can be
deleted with it.

## Settings

Launch MarkyQL.app. Every checkbox applies immediately (autosave) and
takes effect on the next preview. The right pane is a live preview of
either the built-in sample document or any `.md` file you open, so you
can see exactly what a toggle does before you rely on it.

- **Extensions** — the feature list above, one checkbox each.
- **Options** — smart quotes, footnotes, hard/no-soft breaks, unsafe
  inline HTML, UTF-8 validation, render-as-source.
- **Appearance** — GitHub theme or a custom CSS file, base font size,
  and the preferred Quick Look window size (0 = derive the width from
  the theme's `--content-max-width`, the way QLMarkdown does).

Settings are stored in an app-group defaults suite shared by the app,
the extension and the CLI, so all three always agree.

## Command line

`make` also builds `build/markyql` (a copy is inside the app bundle):

```sh
build/markyql notes.md                 # HTML to stdout
build/markyql notes.md -o notes.html
build/markyql notes.md --math          # one-off override, not saved
build/markyql notes.md --no-mermaid
```

Flags: `--math/--no-math`, `--mermaid/--no-mermaid`,
`--emoji/--no-emoji`, `--source` (render as source code),
`--resources <dir>`.

Quick end-to-end check without installing anything:

```sh
make test-render   # renders examples/feature-test.md to build/feature-test.html
open build/feature-test.html
```

## How it works

- `QLExtension/MQPreviewController.m` — a view-based
  `QLPreviewingController` hosting a `WKWebView`. It renders the file
  and hands the HTML to the web view. Nothing else.
- `Shared/MQMarkdown.c` — a small C bridge over
  [cmark-gfm](https://github.com/github/cmark-gfm) (GitHub's own
  parser, MIT). It attaches the GFM core extensions, then walks the
  AST: ` ```mermaid ` blocks become `<pre class="mermaid">`, math
  spans become MathJax delimiters, and raw HTML nodes from the source
  are stripped unless unsafe mode is on (MarkyQL's own generated nodes
  are created after the strip, so they always survive).
- `Shared/MQRenderer.m` — everything around the parser: YAML front
  matter, definition lists (pre/post pass), heading anchors and TOC,
  GitHub alerts, the outside-of-code inline passes (`==`, wikilinks,
  emoji, sub/sup), local image inlining, theme assembly, and
  conditional script injection — MathJax and Mermaid are only loaded
  when the document actually uses them.
- `Shared/MQSettings.{h,m}` — the toggle model described above.
- `App/` — the settings app, built entirely in code (no nibs).
- `CLI/` — the `markyql` tool.

## Known limitations

- Definition-list terms and definitions are plain text; inline
  Markdown inside them is not processed.
- Math detection uses GitHub-style guards (no space inside the
  delimiters, no digit after a closing `$`), but a backslash-escaped
  `\$` loses its backslash during parsing and can still act as a
  delimiter. Currency-heavy documents are happiest with Math off —
  which is the default.
- Local image inlining reads files next to the Markdown file. Under
  the app sandbox the extension can be refused those reads; images it
  cannot read are left as relative references.
- No Finder thumbnails (previews only), and links to other `.md`
  files open nothing yet — both are roadmap items.

## License

MIT — see `LICENSE`. Third-party components are listed with their
licenses in `THIRD-PARTY.md`.
