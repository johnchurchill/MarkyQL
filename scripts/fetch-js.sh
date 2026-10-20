#!/bin/sh
# fetch-js.sh — download MarkyQL's pinned JavaScript dependencies and
# emoji data into Resources/js/. Safe to rerun: existing files are kept,
# versioned artifacts are SHA-256 verified. See THIRD-PARTY.md.
set -eu
cd "$(dirname "$0")/.."
JS=Resources/js
mkdir -p "$JS/mathjax" "$JS/mermaid" "$JS/highlight"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

verify() { # file sha256
    echo "$2  $1" | shasum -a 256 -c - >/dev/null || {
        echo "fetch-js: CHECKSUM MISMATCH for $1" >&2; exit 1; }
}

# --- MathJax 4.1.3 (Apache-2.0): components live at the package root ---
if [ ! -f "$JS/mathjax/tex-chtml.js" ]; then
    curl -fL -o "$TMP/mathjax.tgz" \
        https://registry.npmjs.org/mathjax/-/mathjax-4.1.3.tgz
    verify "$TMP/mathjax.tgz" b7109f516f3d842de62b95d653e35fa0976dc223706a2a77440e7f7723f0c54d
    rm -rf "$JS/mathjax"
    mkdir -p "$JS/mathjax"
    tar -xzf "$TMP/mathjax.tgz" -C "$JS/mathjax" --strip-components 1
    echo "fetch-js: MathJax 4.1.3 installed"
fi

# --- MathJax NewCM font 4.1.3 (Apache-2.0) ---
# In v4 the font is its own package. MathJax's component code resolves
# it through the loader's `fonts` path (which MQRenderer.m points at
# the bundled @mathjax folder, so math works fully offline): the font
# files are used at <fonts>/mathjax-newcm-font/chtml/{woff2,dynamic},
# which is the package's own layout — extract it unchanged.
if [ ! -d "$JS/@mathjax/mathjax-newcm-font/chtml" ]; then
    curl -fL -o "$TMP/newcm.tgz" \
        https://registry.npmjs.org/@mathjax/mathjax-newcm-font/-/mathjax-newcm-font-4.1.3.tgz
    verify "$TMP/newcm.tgz" 87d7b869c6a2a6169d9a53acc4eab6c846a9cbe11752738226461bb5070c8b88
    mkdir -p "$TMP/newcm"
    tar -xzf "$TMP/newcm.tgz" -C "$TMP/newcm" --strip-components 1
    rm -rf "$JS/@mathjax"
    mkdir -p "$JS/@mathjax/mathjax-newcm-font"
    cp -R "$TMP/newcm/chtml" "$JS/@mathjax/mathjax-newcm-font/chtml"
    echo "fetch-js: MathJax NewCM font 4.1.3 installed"
fi

# --- Mermaid 12.0.0 (MIT): single-file UMD build ---
if [ ! -f "$JS/mermaid/mermaid.min.js" ]; then
    curl -fL -o "$TMP/mermaid.tgz" \
        https://registry.npmjs.org/mermaid/-/mermaid-12.0.0.tgz
    verify "$TMP/mermaid.tgz" 7df1e7de572d26ea7aca5eaa7b0e77f5caacb63567006f4077c2753d730ffd9d
    tar -xzf "$TMP/mermaid.tgz" -C "$TMP" package/dist/mermaid.min.js
    mv "$TMP/package/dist/mermaid.min.js" "$JS/mermaid/mermaid.min.js"
    echo "fetch-js: Mermaid 12.0.0 installed"
fi

# --- highlight.js 11.9.0 (BSD-3-Clause) + GitHub themes ---
HL=$JS/highlight
if [ ! -f "$HL/highlight.min.js" ]; then
    curl -fL -o "$HL/highlight.min.js" \
        https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/highlight.min.js
    verify "$HL/highlight.min.js" 837a6fa5b0c736b52bbde2b2b6190f305da3fc9ed41681db5321507057b5c846
    echo "fetch-js: highlight.js 11.9.0 installed"
fi
if [ ! -f "$HL/hljs-theme.css" ]; then
    curl -fL -o "$TMP/hljs-light.css" \
        https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/styles/github.min.css
    verify "$TMP/hljs-light.css" 3a9a5def8b9c311e5ae43abde85c63133185eed4f0d9f67fea4b00a8308cf066
    curl -fL -o "$TMP/hljs-dark.css" \
        https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/styles/github-dark.min.css
    verify "$TMP/hljs-dark.css" 9f208d022102b1d0c7aebfecd8e42ca7997d5de636649d2b31ea63093d809019
    { cat "$TMP/hljs-light.css"
      printf '\n@media (prefers-color-scheme: dark) {\n'
      cat "$TMP/hljs-dark.css"
      printf '\n}\n'
    } > "$HL/hljs-theme.css"
    echo "fetch-js: highlight.js themes installed"
fi

# --- gemoji database (MIT), pinned by commit ---
if [ ! -f "$JS/emoji.json" ]; then
    curl -fL -o "$JS/emoji.json" \
        https://raw.githubusercontent.com/github/gemoji/fadaeaf1f1a9be82b321316a6c5502e43138b2f6/db/emoji.json
    echo "fetch-js: gemoji database installed"
fi

echo "fetch-js: all dependencies present"
