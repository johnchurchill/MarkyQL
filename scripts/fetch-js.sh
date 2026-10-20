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

# --- MathJax 3.2.2 (Apache-2.0): the whole es5 tree, tex-chtml entry ---
if [ ! -f "$JS/mathjax/es5/tex-chtml.js" ]; then
    curl -fL -o "$TMP/mathjax.tgz" \
        https://registry.npmjs.org/mathjax/-/mathjax-3.2.2.tgz
    verify "$TMP/mathjax.tgz" 1b9c0a1c44df864e915690558e72adb9cc5203360daefd385084ced3b6c64c09
    tar -xzf "$TMP/mathjax.tgz" -C "$TMP" package/es5
    rm -rf "$JS/mathjax/es5"
    mv "$TMP/package/es5" "$JS/mathjax/es5"
    echo "fetch-js: MathJax 3.2.2 installed"
fi

# --- Mermaid 11.4.1 (MIT): single-file UMD build ---
if [ ! -f "$JS/mermaid/mermaid.min.js" ]; then
    curl -fL -o "$TMP/mermaid.tgz" \
        https://registry.npmjs.org/mermaid/-/mermaid-11.4.1.tgz
    verify "$TMP/mermaid.tgz" ec7b61b391aaa24bf666fd20e48d0a626eeb4a95b95bc6b3016a122d7f0bc2af
    tar -xzf "$TMP/mermaid.tgz" -C "$TMP" package/dist/mermaid.min.js
    mv "$TMP/package/dist/mermaid.min.js" "$JS/mermaid/mermaid.min.js"
    echo "fetch-js: Mermaid 11.4.1 installed"
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
