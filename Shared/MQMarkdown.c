//
//  MQMarkdown.c
//  MarkyQL
//
//  cmark-gfm bridge plus AST transforms for math and mermaid.
//  Written from scratch for MarkyQL; no QLMarkdown code.
//

#include "MQMarkdown.h"

#include <stdlib.h>
#include <string.h>

#include <cmark-gfm.h>
#include <cmark-gfm-core-extensions.h>
#include <cmark-gfm-extension_api.h>

// ---------------------------------------------------------------------------
// Small growable string buffer (plain malloc).

typedef struct {
    char *buf;
    size_t len;
    size_t cap;
} mq_str;

static void mq_str_init(mq_str *s) {
    s->cap = 128;
    s->len = 0;
    s->buf = (char *)malloc(s->cap);
    s->buf[0] = '\0';
}

static void mq_str_append_n(mq_str *s, const char *p, size_t n) {
    if (s->len + n + 1 > s->cap) {
        while (s->len + n + 1 > s->cap) s->cap *= 2;
        s->buf = (char *)realloc(s->buf, s->cap);
    }
    memcpy(s->buf + s->len, p, n);
    s->len += n;
    s->buf[s->len] = '\0';
}

static void mq_str_append(mq_str *s, const char *p) {
    mq_str_append_n(s, p, strlen(p));
}

/// Append src with &, <, > escaped for HTML element content.
static void mq_str_append_escaped(mq_str *s, const char *p, size_t n) {
    for (size_t i = 0; i < n; i++) {
        switch (p[i]) {
            case '&': mq_str_append(s, "&amp;"); break;
            case '<': mq_str_append(s, "&lt;"); break;
            case '>': mq_str_append(s, "&gt;"); break;
            default: mq_str_append_n(s, p + i, 1); break;
        }
    }
}

// ---------------------------------------------------------------------------
// AST helpers.

/// Snapshot a node's children into a malloc'd array (count in *out_count).
/// Node surgery during iteration can then never invalidate the walk.
static cmark_node **mq_children(cmark_node *node, size_t *out_count) {
    size_t count = 0, cap = 8;
    cmark_node **arr = (cmark_node **)malloc(cap * sizeof(cmark_node *));
    for (cmark_node *c = cmark_node_first_child(node); c; c = cmark_node_next(c)) {
        if (count == cap) {
            cap *= 2;
            arr = (cmark_node **)realloc(arr, cap * sizeof(cmark_node *));
        }
        arr[count++] = c;
    }
    *out_count = count;
    return arr;
}

static void mq_replace_node(cmark_node *old_node, cmark_node *replacement) {
    cmark_node_insert_before(old_node, replacement);
    cmark_node_unlink(old_node);
    cmark_node_free(old_node);
}

// ---------------------------------------------------------------------------
// Raw HTML stripping (unsafe mode off). Our own generated HTML nodes are
// only created after this pass, so rendering with CMARK_OPT_UNSAFE later
// is safe: nothing user-supplied survives to be passed through.

static void mq_strip_html(cmark_node *node) {
    size_t count;
    cmark_node **kids = mq_children(node, &count);
    for (size_t i = 0; i < count; i++) {
        cmark_node_type t = cmark_node_get_type(kids[i]);
        if (t == CMARK_NODE_HTML_BLOCK || t == CMARK_NODE_HTML_INLINE) {
            cmark_node_unlink(kids[i]);
            cmark_node_free(kids[i]);
        } else {
            mq_strip_html(kids[i]);
        }
    }
    free(kids);
}

// ---------------------------------------------------------------------------
// Math.
//
// Inline: $...$ -> <span class="math math-inline">\(...\)</span>
// Display: $$...$$ as a whole paragraph (or inline span) ->
//          <div class="math math-display">\[...\]</div>
// Guards mirror GitHub's: the opening delimiter may not be followed by
// whitespace, the closing one may not be preceded by whitespace, and an
// inline closing $ may not be followed by a digit (currency like
// "$5 and $10" stays text). Known limitation: a backslash-escaped \$
// loses its backslash during parsing and can act as a delimiter.

static bool mq_is_space(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

/// Find a closing delimiter at or after `from`. For inline math the
/// delimiter is a single '$', for display '$$'. Returns -1 if none valid.
static long mq_find_close(const char *s, size_t len, size_t from, bool display) {
    for (size_t i = from; i < len; i++) {
        if (s[i] != '$') continue;
        if (display) {
            if (i + 1 < len && s[i + 1] == '$' && i > from && !mq_is_space(s[i - 1])) {
                return (long)i;
            }
        } else {
            if (i > from && !mq_is_space(s[i - 1])) {
                size_t after = i + 1;
                if (after < len && s[after] >= '0' && s[after] <= '9') continue;
                // not part of a $$ pair
                if (after < len && s[after] == '$') continue;
                if (i > 0 && s[i - 1] == '$') continue;
                return (long)i;
            }
        }
    }
    return -1;
}

static cmark_node *mq_new_text(cmark_mem *mem, const char *p, size_t n) {
    cmark_node *node = cmark_node_new_with_mem(CMARK_NODE_TEXT, mem);
    char *tmp = (char *)malloc(n + 1);
    memcpy(tmp, p, n);
    tmp[n] = '\0';
    cmark_node_set_literal(node, tmp);
    free(tmp);
    return node;
}

static cmark_node *mq_new_math_span(cmark_mem *mem, const char *tex, size_t n, bool display) {
    mq_str s;
    mq_str_init(&s);
    if (display) mq_str_append(&s, "<span class=\"math math-display\">\\[");
    else         mq_str_append(&s, "<span class=\"math math-inline\">\\(");
    mq_str_append_escaped(&s, tex, n);
    mq_str_append(&s, display ? "\\]</span>" : "\\)</span>");
    cmark_node *node = cmark_node_new_with_mem(CMARK_NODE_HTML_INLINE, mem);
    cmark_node_set_literal(node, s.buf);
    free(s.buf);
    return node;
}

/// Split a TEXT node's literal on math delimiters, replacing the node
/// with a sequence of TEXT / HTML_INLINE siblings.
static void mq_split_math(cmark_node *text_node, cmark_mem *mem) {
    const char *s = cmark_node_get_literal(text_node);
    if (!s || !strchr(s, '$')) return;
    size_t len = strlen(s);

    bool any = false;
    size_t pos = 0;   // emit cursor: everything before pos is emitted
    size_t scan = 0;  // search cursor for the next opening delimiter
    while (scan < len) {
        // Find the next potential opening delimiter at or after scan.
        size_t open = scan;
        bool display = false;
        bool found = false;
        while (open < len) {
            if (s[open] == '$') {
                if (open + 1 < len && s[open + 1] == '$') {
                    if (open + 2 < len && !mq_is_space(s[open + 2])) { display = true; found = true; break; }
                } else if (open + 1 < len && !mq_is_space(s[open + 1])) {
                    found = true; break;
                }
            }
            open++;
        }
        if (!found) break;
        size_t tex_start = open + (display ? 2 : 1);
        long close = mq_find_close(s, len, tex_start, display);
        if (close < 0) {
            // Not actually math; resume the search after this '$',
            // leaving the emit cursor (and its text) untouched.
            scan = open + 1;
            continue;
        }
        // Emit preceding text and the math span.
        if (open > pos) {
            cmark_node_insert_before(text_node, mq_new_text(mem, s + pos, open - pos));
        }
        cmark_node_insert_before(text_node,
            mq_new_math_span(mem, s + tex_start, (size_t)close - tex_start, display));
        any = true;
        pos = (size_t)close + (display ? 2 : 1);
        scan = pos;
    }
    if (!any) return;
    if (pos < len) {
        cmark_node_insert_before(text_node, mq_new_text(mem, s + pos, len - pos));
    }
    cmark_node_unlink(text_node);
    cmark_node_free(text_node);
}

/// A paragraph consisting solely of $$...$$ becomes a display block.
/// The paragraph's text may be split across several TEXT nodes by
/// SOFTBREAKs, so collect the full text first.
static bool mq_try_block_math(cmark_node *paragraph, cmark_mem *mem) {
    mq_str text;
    mq_str_init(&text);
    for (cmark_node *child = cmark_node_first_child(paragraph); child;
         child = cmark_node_next(child)) {
        cmark_node_type t = cmark_node_get_type(child);
        if (t == CMARK_NODE_TEXT) {
            const char *lit = cmark_node_get_literal(child);
            if (lit) mq_str_append(&text, lit);
        } else if (t == CMARK_NODE_SOFTBREAK) {
            mq_str_append(&text, "\n");
        } else {
            free(text.buf);
            return false;
        }
    }
    const char *s = text.buf;
    // Trim.
    while (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r') s++;
    size_t n = strlen(s);
    while (n > 0 && (s[n - 1] == ' ' || s[n - 1] == '\t' || s[n - 1] == '\n' || s[n - 1] == '\r')) n--;
    if (n < 5 || s[0] != '$' || s[1] != '$' || s[n - 2] != '$' || s[n - 1] != '$') {
        free(text.buf);
        return false;
    }

    mq_str out;
    mq_str_init(&out);
    mq_str_append(&out, "<div class=\"math math-display\">\\[");
    mq_str_append_escaped(&out, s + 2, n - 4);
    mq_str_append(&out, "\\]</div>\n");
    free(text.buf);
    cmark_node *block = cmark_node_new_with_mem(CMARK_NODE_HTML_BLOCK, mem);
    cmark_node_set_literal(block, out.buf);
    free(out.buf);
    mq_replace_node(paragraph, block);
    return true;
}

// ---------------------------------------------------------------------------
// Mermaid: ```mermaid fenced block -> <pre class="mermaid">...</pre>

static void mq_try_mermaid(cmark_node *code_block, cmark_mem *mem) {
    const char *info = cmark_node_get_fence_info(code_block);
    if (!info) return;
    // First word of the info string must be "mermaid".
    while (*info == ' ' || *info == '\t') info++;
    if (strncmp(info, "mermaid", 7) != 0) return;
    if (info[7] != '\0' && info[7] != ' ' && info[7] != '\t') return;

    const char *code = cmark_node_get_literal(code_block);
    if (!code) code = "";
    mq_str out;
    mq_str_init(&out);
    mq_str_append(&out, "<pre class=\"mermaid\">\n");
    mq_str_append_escaped(&out, code, strlen(code));
    mq_str_append(&out, "</pre>\n");
    cmark_node *block = cmark_node_new_with_mem(CMARK_NODE_HTML_BLOCK, mem);
    cmark_node_set_literal(block, out.buf);
    free(out.buf);
    mq_replace_node(code_block, block);
}

// ---------------------------------------------------------------------------
// Recursive transform walk.

static void mq_transform(cmark_node *node, const MQMarkdownOptions *o, cmark_mem *mem) {
    size_t count;
    cmark_node **kids = mq_children(node, &count);
    for (size_t i = 0; i < count; i++) {
        cmark_node *child = kids[i];
        cmark_node_type t = cmark_node_get_type(child);
        if (t == CMARK_NODE_PARAGRAPH && o->math && mq_try_block_math(child, mem)) {
            continue; // replaced by an HTML block; nothing to recurse into
        }
        if (t == CMARK_NODE_CODE_BLOCK && o->mermaid) {
            mq_try_mermaid(child, mem);
            continue;
        }
        if (t == CMARK_NODE_TEXT && o->math) {
            mq_split_math(child, mem);
            continue;
        }
        mq_transform(child, o, mem);
    }
    free(kids);
}

// ---------------------------------------------------------------------------
// Entry point.

char *mq_markdown_to_html(const char *markdown_utf8, const MQMarkdownOptions *o) {
    if (!markdown_utf8 || !o) return NULL;

    cmark_gfm_core_extensions_ensure_registered();
    cmark_mem *mem = cmark_get_default_mem_allocator();

    int parser_options = CMARK_OPT_DEFAULT;
    if (o->footnotes) parser_options |= CMARK_OPT_FOOTNOTES;
    if (o->smart) parser_options |= CMARK_OPT_SMART;
    if (o->validate_utf8) parser_options |= CMARK_OPT_VALIDATE_UTF8;
    if (o->strikethrough_double_tilde) parser_options |= CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE;

    cmark_parser *parser = cmark_parser_new_with_mem(parser_options, mem);
    if (!parser) return NULL;

    struct { bool on; const char *name; } exts[] = {
        { o->ext_table, "table" },
        { o->ext_strikethrough, "strikethrough" },
        { o->ext_autolink, "autolink" },
        { o->ext_tagfilter, "tagfilter" },
        { o->ext_tasklist, "tasklist" },
    };
    for (size_t i = 0; i < sizeof(exts) / sizeof(exts[0]); i++) {
        if (!exts[i].on) continue;
        cmark_syntax_extension *ext = cmark_find_syntax_extension(exts[i].name);
        if (ext) cmark_parser_attach_syntax_extension(parser, ext);
    }

    cmark_parser_feed(parser, markdown_utf8, strlen(markdown_utf8));
    cmark_node *doc = cmark_parser_finish(parser);
    if (!doc) {
        cmark_parser_free(parser);
        return NULL;
    }

    if (!o->unsafe_html) mq_strip_html(doc);
    if (o->math || o->mermaid) mq_transform(doc, o, mem);

    int render_options = CMARK_OPT_UNSAFE; // our generated nodes must pass;
                                             // user HTML was stripped above
    if (o->hard_breaks) render_options |= CMARK_OPT_HARDBREAKS;
    if (o->no_soft_breaks) render_options |= CMARK_OPT_NOBREAKS;

    char *html = cmark_render_html_with_mem(doc,
                                            render_options,
                                            cmark_parser_get_syntax_extensions(parser),
                                            mem);
    cmark_node_free(doc);
    cmark_parser_free(parser);
    return html;
}
