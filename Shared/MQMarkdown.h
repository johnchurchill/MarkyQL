//
//  MQMarkdown.h
//  MarkyQL
//
//  Thin C bridge over cmark-gfm (MIT, github.com/github/cmark-gfm).
//  Handles the parser-level work: GFM core extensions, math spans,
//  mermaid blocks, and stripping raw HTML when unsafe mode is off.
//

#ifndef MQ_MARKDOWN_H
#define MQ_MARKDOWN_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    // parser options
    bool footnotes;
    bool smart;
    bool unsafe_html;     // if false, raw HTML nodes from the source are removed
    bool validate_utf8;
    // render options
    bool hard_breaks;
    bool no_soft_breaks;
    bool strikethrough_double_tilde; // require ~~ (needed when ~sub~ is on)
    // cmark-gfm core extensions
    bool ext_table;
    bool ext_strikethrough;
    bool ext_autolink;
    bool ext_tagfilter;
    bool ext_tasklist;
    // MarkyQL AST transforms
    bool math;            // $...$ and $$...$$ -> MathJax delimiters
    bool mermaid;         // ```mermaid fenced blocks -> <pre class="mermaid">
} MQMarkdownOptions;

/// Render UTF-8 markdown to an HTML fragment.
/// Returns a malloc'd string the caller must free(), or NULL on failure.
char *mq_markdown_to_html(const char *markdown_utf8, const MQMarkdownOptions *options);

#ifdef __cplusplus
}
#endif

#endif /* MQ_MARKDOWN_H */
