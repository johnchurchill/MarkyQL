//
//  MQRenderer.m
//  MarkyQL
//

#import "MQRenderer.h"
#import "MQMarkdown.h"

@interface MQRenderer ()
@property (nonatomic, strong) NSURL *resourceURL;
@property (nonatomic, strong) MQSettings *settings;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *emojiMap;
@end

@implementation MQRenderer

- (instancetype)initWithResourceURL:(NSURL *)resourceURL settings:(MQSettings *)settings {
    self = [super init];
    if (self) {
        _resourceURL = resourceURL;
        _settings = settings;
    }
    return self;
}

#pragma mark - file loading

+ (NSURL *)resolveMarkdownFileURL:(NSURL *)url {
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDir] || !isDir) {
        return url;
    }
    // Textbundle package: the markdown lives in a well-known file inside.
    for (NSString *name in @[@"text.md", @"text.markdown", @"text.txt", @"text.mark.md"]) {
        NSURL *candidate = [url URLByAppendingPathComponent:name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) return candidate;
    }
    return url;
}

- (NSString *)readTextFile:(NSURL *)url error:(NSError **)error {
    NSStringEncoding used = 0;
    NSString *text = [NSString stringWithContentsOfURL:url usedEncoding:&used error:error];
    if (text) return text;
    // Fall back through common legacy encodings (older GBK/Big5/Shift_JIS
    // files are deliberately NOT guessed: a wrong guess is worse than an
    // error. UTF-8 and the Windows Latin pages cover most real cases.)
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) return nil;
    for (NSNumber *enc in @[@(NSUTF8StringEncoding),
                            @(NSWindowsCP1252StringEncoding),
                            @(NSISOLatin1StringEncoding)]) {
        text = [[NSString alloc] initWithData:data encoding:enc.unsignedIntegerValue];
        if (text) return text;
    }
    return nil;
}

- (NSString *)renderFileAtURL:(NSURL *)url error:(NSError **)error {
    NSURL *mdURL = [MQRenderer resolveMarkdownFileURL:url];
    NSString *text = [self readTextFile:mdURL error:error];
    if (!text) return nil;
    // A bare .mermaid file is a diagram, not prose: wrap it in a fenced
    // block so it renders as one (same behaviour as QLMarkdown).
    if ([mdURL.pathExtension.lowercaseString isEqualToString:@"mermaid"]) {
        text = [NSString stringWithFormat:@"```mermaid\n%@\n```\n", text];
    }
    return [self renderMarkdown:text
                    sourceName:mdURL.lastPathComponent
                 baseDirectory:mdURL.URLByDeletingLastPathComponent];
}

#pragma mark - small helpers

- (NSString *)escapeHTML:(NSString *)s {
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    s = [s stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    s = [s stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    return s;
}

/// Apply `transform` only to the parts of the HTML outside <pre>/<code>.
- (NSString *)processOutsideCode:(NSString *)html
                       transform:(NSString * (^)(NSString *segment))transform {
    static NSRegularExpression *codeRe;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        codeRe = [NSRegularExpression regularExpressionWithPattern:
                  @"(<pre\\b[^>]*>[\\s\\S]*?</pre>|<code\\b[^>]*>[\\s\\S]*?</code>)"
                                                            options:0 error:nil];
    });
    NSMutableString *result = [NSMutableString string];
    NSUInteger pos = 0;
    for (NSTextCheckingResult *m in [codeRe matchesInString:html options:0
                                                       range:NSMakeRange(0, html.length)]) {
        NSRange before = NSMakeRange(pos, m.range.location - pos);
        [result appendString:transform([html substringWithRange:before])];
        [result appendString:[html substringWithRange:m.range]];
        pos = m.range.location + m.range.length;
    }
    [result appendString:transform([html substringFromIndex:pos])];
    return result;
}

- (NSString *)replace:(NSString *)pattern in:(NSString *)s withTemplate:(NSString *)tmpl {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                          options:0 error:nil];
    return [re stringByReplacingMatchesInString:s options:0
                                          range:NSMakeRange(0, s.length) withTemplate:tmpl];
}

#pragma mark - YAML front matter

/// If the source opens with a --- fence, returns the fenced block parsed
/// as flat key:value pairs and (via outSource) the remaining markdown.
- (NSDictionary<NSString *, NSString *> *)extractFrontMatter:(NSString *)source
                                                   remaining:(NSString **)outSource {
    if (![source hasPrefix:@"---\n"] && ![source hasPrefix:@"---\r\n"]) return nil;
    NSArray<NSString *> *lines = [source componentsSeparatedByString:@"\n"];
    NSMutableDictionary *meta = [NSMutableDictionary dictionary];
    NSUInteger i = 1;
    for (; i < lines.count; i++) {
        NSString *line = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([line isEqualToString:@"---"] || [line isEqualToString:@"..."]) break;
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location != NSNotFound) {
            NSString *key = [[line substringToIndex:colon.location]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *value = [[line substringFromIndex:colon.location + 1]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (key.length) meta[key] = value;
        }
    }
    if (i >= lines.count) return nil; // no closing fence: not front matter
    *outSource = [[lines subarrayWithRange:NSMakeRange(i + 1, lines.count - i - 1)]
                  componentsJoinedByString:@"\n"];
    return meta;
}

- (NSString *)frontMatterTable:(NSDictionary<NSString *, NSString *> *)meta {
    NSMutableString *html = [NSMutableString stringWithString:
        @"<table class=\"mq-front-matter\"><tbody>"];
    for (NSString *key in [meta.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [html appendFormat:@"<tr><th>%@</th><td>%@</td></tr>",
            [self escapeHTML:key], [self escapeHTML:meta[key]]];
    }
    [html appendString:@"</tbody></table>\n"];
    return html;
}

#pragma mark - definition lists (pre/post pass around cmark)
//
// cmark-gfm has no definition-list extension, so a term line followed by
// ": definition" lines is rewritten to a placeholder paragraph before
// parsing and swapped for a <dl> afterwards. Term and definition text is
// plain (inline markdown inside them is not processed).

- (NSString *)extractDefinitionLists:(NSString *)source store:(NSMutableArray<NSString *> *)store {
    NSArray<NSString *> *lines = [source componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSUInteger i = 0;
    while (i < lines.count) {
        // Collect candidate term lines.
        NSUInteger j = i;
        NSMutableArray<NSString *> *terms = [NSMutableArray array];
        while (j < lines.count) {
            NSString *t = [lines[j] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (t.length == 0 || [t hasPrefix:@"#"] || [t hasPrefix:@":"] ||
                [t hasPrefix:@"```"] || [t hasPrefix:@">"]) break;
            [terms addObject:lines[j]];
            j++;
            // Only continue gathering terms if the line after is another
            // term or a ": " definition line.
            if (j < lines.count && ![lines[j] hasPrefix:@": "] && terms.count > 0) {
                NSString *next = [lines[j] stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]];
                if (next.length == 0) { terms = nil; break; }
            }
        }
        NSMutableArray<NSString *> *defs = [NSMutableArray array];
        NSUInteger k = j;
        if (terms.count) {
            while (k < lines.count && [lines[k] hasPrefix:@": "]) {
                [defs addObject:[lines[k] substringFromIndex:2]];
                k++;
            }
        }
        if (terms.count && defs.count) {
            NSMutableString *dl = [NSMutableString stringWithString:@"<dl>"];
            for (NSString *t in terms) [dl appendFormat:@"<dt>%@</dt>", [self escapeHTML:t]];
            for (NSString *d in defs) [dl appendFormat:@"<dd>%@</dd>", [self escapeHTML:d]];
            [dl appendString:@"</dl>"];
            [store addObject:dl];
            [out addObject:[NSString stringWithFormat:@"MQDEFLISTPLACEHOLDER%lu",
                            (unsigned long)(store.count - 1)]];
            [out addObject:@""];
            i = k;
        } else {
            [out addObject:lines[i]];
            i++;
        }
    }
    return [out componentsJoinedByString:@"\n"];
}

- (NSString *)restoreDefinitionLists:(NSString *)html store:(NSArray<NSString *> *)store {
    for (NSUInteger idx = 0; idx < store.count; idx++) {
        NSString *placeholder = [NSString stringWithFormat:@"<p>MQDEFLISTPLACEHOLDER%lu</p>",
                                 (unsigned long)idx];
        html = [html stringByReplacingOccurrencesOfString:placeholder withString:store[idx]];
    }
    return html;
}

#pragma mark - heading anchors + TOC

- (NSString *)slugForHeadingText:(NSString *)text {
    NSMutableString *slug = [NSMutableString string];
    NSCharacterSet *keep = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if ([keep characterIsMember:c] || c == '-' || c == '_') {
            [slug appendString:[[NSString stringWithCharacters:&c length:1] lowercaseString]];
        } else if (c == ' ' || c == '\t') {
            [slug appendString:@"-"];
        }
    }
    return slug;
}

- (NSString *)stripTags:(NSString *)html {
    return [self replace:@"<[^>]+>" in:html withTemplate:@""];
}

/// Adds id attributes to headings (when addIDs) and returns the heading
/// list (level/slug/text dictionaries) via `headings`.
- (NSString *)processHeadings:(NSString *)html addIDs:(BOOL)addIDs
                     headings:(NSMutableArray<NSDictionary *> *)headings {
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"<h([1-6])([^>]*)>([\\s\\S]*?)</h\\1>"
                             options:0 error:nil];
    NSMutableString *result = [NSMutableString string];
    NSMutableSet<NSString *> *used = [NSMutableSet set];
    NSUInteger pos = 0;
    for (NSTextCheckingResult *m in [re matchesInString:html options:0
                                                  range:NSMakeRange(0, html.length)]) {
        [result appendString:[html substringWithRange:NSMakeRange(pos, m.range.location - pos)]];
        NSString *whole = [html substringWithRange:m.range];
        NSString *level = [html substringWithRange:[m rangeAtIndex:1]];
        NSString *attrs = [html substringWithRange:[m rangeAtIndex:2]];
        NSString *inner = [html substringWithRange:[m rangeAtIndex:3]];
        NSString *text = [self stripTags:inner];
        text = [text stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        NSString *slug = [self slugForHeadingText:text];
        if (slug.length) {
            NSString *base = slug;
            NSUInteger n = 1;
            while ([used containsObject:slug]) slug = [NSString stringWithFormat:@"%@-%lu", base, (unsigned long)n++];
            [used addObject:slug];
            [headings addObject:@{@"level": @([level intValue]), @"slug": slug, @"text": text}];
            if (addIDs && ![attrs containsString:@" id="]) {
                whole = [NSString stringWithFormat:@"<h%@ id=\"%@\"%@>%@</h%@>",
                         level, slug, attrs, inner, level];
            }
        }
        [result appendString:whole];
        pos = m.range.location + m.range.length;
    }
    [result appendString:[html substringFromIndex:pos]];
    return result;
}

- (NSString *)tableOfContents:(NSArray<NSDictionary *> *)headings {
    NSMutableString *html = [NSMutableString stringWithString:
        @"<nav class=\"mq-toc\"><p class=\"mq-toc-title\">Contents</p><ul>"];
    for (NSDictionary *h in headings) {
        [html appendFormat:@"<li class=\"mq-toc-h%@\"><a href=\"#%@\">%@</a></li>",
            h[@"level"], h[@"slug"], [self escapeHTML:h[@"text"]]];
    }
    [html appendString:@"</ul></nav>\n"];
    return html;
}

#pragma mark - GitHub alerts

- (NSString *)processAlerts:(NSString *)html {
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:
            @"<blockquote>\\s*<p>\\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\][ \\t]*(<br\\s*/?>)?[ \\t]*\n?"
                             options:NSRegularExpressionCaseInsensitive error:nil];
    NSMutableString *result = [html mutableCopy];
    NSUInteger pos = 0;
    while (YES) {
        NSTextCheckingResult *m = [re firstMatchInString:result options:0
                                                   range:NSMakeRange(pos, result.length - pos)];
        if (!m) break;
        NSString *type = [[result substringWithRange:[m rangeAtIndex:1]] lowercaseString];
        NSString *title = [type capitalizedString];
        NSUInteger matchEnd = m.range.location + m.range.length;
        // Marker alone in its paragraph (rest starts with </p>): swallow
        // that close tag and don't open a new paragraph. Otherwise the
        // marker shared its paragraph with text: open one for the rest.
        BOOL markerOnly = [[result substringFromIndex:matchEnd] hasPrefix:@"</p>"];
        NSString *open = [NSString stringWithFormat:
            @"<div class=\"markdown-alert markdown-alert-%@\">"
            @"<p class=\"markdown-alert-title\">%@</p>%@",
            type, title, markerOnly ? @"" : @"<p>"];
        NSRange replaceRange = markerOnly
            ? NSMakeRange(m.range.location, m.range.length + 4)
            : m.range;
        [result replaceCharactersInRange:replaceRange withString:open];
        NSUInteger contentStart = m.range.location + open.length;
        NSRange close = [result rangeOfString:@"</blockquote>"
                                      options:0
                                        range:NSMakeRange(contentStart, result.length - contentStart)];
        if (close.location != NSNotFound) {
            [result replaceCharactersInRange:close withString:@"</div>"];
        }
        pos = contentStart;
    }
    return result;
}

#pragma mark - inline passes (outside code)

- (NSDictionary<NSString *, NSString *> *)emojiMap {
    if (_emojiMap) return _emojiMap;
    _emojiMap = @{};
    NSURL *url = [[self.resourceURL URLByAppendingPathComponent:@"js"]
                  URLByAppendingPathComponent:@"emoji.json"];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data) {
        NSArray *entries = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([entries isKindOfClass:[NSArray class]]) {
            NSMutableDictionary *map = [NSMutableDictionary dictionary];
            for (NSDictionary *e in entries) {
                NSString *emoji = e[@"emoji"];
                if (![emoji isKindOfClass:[NSString class]]) continue;
                for (NSString *alias in e[@"aliases"] ?: @[]) map[alias] = emoji;
            }
            _emojiMap = map;
        }
    }
    return _emojiMap;
}

- (NSString *)inlinePasses:(NSString *)html {
    MQSettings *st = self.settings;
    return [self processOutsideCode:html transform:^NSString *(NSString *segment) {
        NSString *s = segment;
        if (st.extWikilinks) {
            s = [self replace:@"\\[\\[([^\\]|]+)(?:\\|([^\\]]+))?\\]\\]" in:s
                 withTemplate:@"<a href=\"$1\">$2</a>"];
            // [[Target]] without a display part leaves an empty link text;
            // fix those up with the target as the text.
            s = [self replace:@"<a href=\"([^\"]+)\"></a>" in:s withTemplate:@"<a href=\"$1\">$1</a>"];
        }
        if (st.extEmoji) {
            NSDictionary *map = [self emojiMap];
            if (map.count) {
                NSRegularExpression *re = [NSRegularExpression
                    regularExpressionWithPattern:@":([a-z0-9_+\\-]+):" options:0 error:nil];
                NSMutableString *ms = [s mutableCopy];
                NSArray<NSTextCheckingResult *> *matches =
                    [re matchesInString:s options:0 range:NSMakeRange(0, s.length)];
                for (NSTextCheckingResult *m in [matches reverseObjectEnumerator]) {
                    NSString *emoji = map[[s substringWithRange:[m rangeAtIndex:1]]];
                    if (emoji) [ms replaceCharactersInRange:m.range withString:emoji];
                }
                s = ms;
            }
        }
        if (st.extHighlight) {
            s = [self replace:@"==([^=\\s][^=]*?)==" in:s withTemplate:@"<mark>$1</mark>"];
        }
        if (st.extSubSuperscript) {
            s = [self replace:@"~([^~\\s][^~]*?)~" in:s withTemplate:@"<sub>$1</sub>"];
            s = [self replace:@"\\^([^\\^\\s][^\\^]*?)\\^" in:s withTemplate:@"<sup>$1</sup>"];
        }
        return s;
    }];
}

#pragma mark - local image inlining
//
// The Quick Look sandbox cannot open files sitting next to the markdown
// file, so local images are embedded as data: URIs (same approach as
// QLMarkdown). Runs last so no other pass can touch the base64 payload.

- (NSString *)inlineLocalImages:(NSString *)html baseDirectory:(NSURL *)baseDirectory {
    static NSDictionary *mimes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        mimes = @{@"png": @"image/png", @"jpg": @"image/jpeg", @"jpeg": @"image/jpeg",
                  @"gif": @"image/gif", @"webp": @"image/webp", @"svg": @"image/svg+xml",
                  @"bmp": @"image/bmp", @"ico": @"image/x-icon"};
    });
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"(<img\\b[^>]*?\\bsrc=\")([^\"]+)(\")"
                             options:0 error:nil];
    NSMutableString *result = [html mutableCopy];
    NSArray<NSTextCheckingResult *> *matches =
        [re matchesInString:html options:0 range:NSMakeRange(0, html.length)];
    for (NSTextCheckingResult *m in [matches reverseObjectEnumerator]) {
        NSString *src = [html substringWithRange:[m rangeAtIndex:2]];
        if ([src hasPrefix:@"data:"]) continue;
        NSString *path = nil;
        if ([src hasPrefix:@"file://"]) {
            path = [NSURL URLWithString:src].path;
        } else if ([src containsString:@"://"]) {
            continue; // remote image: leave it (no network in the sandbox)
        } else {
            path = [baseDirectory.path stringByAppendingPathComponent:
                    [src stringByRemovingPercentEncoding] ?: src];
        }
        NSString *mime = mimes[path.pathExtension.lowercaseString];
        if (!mime) continue;
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data || data.length > 10 * 1024 * 1024) continue;
        NSString *uri = [NSString stringWithFormat:@"data:%@;base64,%@",
                         mime, [data base64EncodedStringWithOptions:0]];
        [result replaceCharactersInRange:[m rangeAtIndex:2] withString:uri];
    }
    return result;
}

#pragma mark - theme

- (NSString *)themeCSS {
    MQSettings *st = self.settings;
    if ([st.themeName isEqualToString:@"custom"] && st.customCSSPath) {
        NSString *css = [NSString stringWithContentsOfFile:st.customCSSPath
                                                  encoding:NSUTF8StringEncoding error:nil];
        if (css) return css;
    }
    NSURL *url = [[self.resourceURL URLByAppendingPathComponent:@"themes"]
                  URLByAppendingPathComponent:[st.themeName stringByAppendingPathExtension:@"css"]];
    NSString *css = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    return css ?: @"body{font-family:-apple-system,Helvetica,Arial,sans-serif;margin:2em;}";
}

- (NSString *)highlightThemeCSS {
    NSURL *url = [[[self.resourceURL URLByAppendingPathComponent:@"js"]
                   URLByAppendingPathComponent:@"highlight"]
                  URLByAppendingPathComponent:@"hljs-theme.css"];
    return [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] ?: @"";
}

- (CGSize)preferredPreviewSize {
    MQSettings *st = self.settings;
    double width = st.previewWidth;
    if (width <= 0) {
        NSString *css = [self themeCSS];
        NSRegularExpression *re = [NSRegularExpression
            regularExpressionWithPattern:@"--content-max-width:\\s*(\\d+)px" options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:css options:0
                                                   range:NSMakeRange(0, css.length)];
        width = m ? [[css substringWithRange:[m rangeAtIndex:1]] doubleValue] : 960;
    }
    double height = st.previewHeight > 0 ? st.previewHeight : 1000;
    return CGSizeMake(width, height);
}

#pragma mark - main pipeline

- (NSString *)renderMarkdown:(NSString *)source
                 sourceName:(NSString *)sourceName
              baseDirectory:(NSURL *)baseDirectory {
    MQSettings *st = self.settings;
    NSString *body;
    BOOL hasMath = NO, hasMermaid = NO, hasCode = NO;

    if (st.optRenderAsSource) {
        body = [NSString stringWithFormat:@"<pre><code class=\"language-markdown\">%@</code></pre>",
                [self escapeHTML:source]];
        hasCode = YES;
    } else {
        NSString *src = source;
        NSString *frontTable = @"";
        if (st.extYAMLHeader) {
            NSString *rest = nil;
            NSDictionary *meta = [self extractFrontMatter:src remaining:&rest];
            if (meta) {
                src = rest;
                frontTable = [self frontMatterTable:meta];
            }
        }
        NSMutableArray<NSString *> *dlStore = [NSMutableArray array];
        if (st.extDefinitionList) src = [self extractDefinitionLists:src store:dlStore];

        MQMarkdownOptions o = {0};
        o.footnotes = st.optFootnotes;
        o.smart = st.optSmartQuotes;
        o.unsafe_html = st.optUnsafeHTML;
        o.validate_utf8 = st.optValidateUTF8;
        o.hard_breaks = st.optHardBreaks;
        o.no_soft_breaks = st.optNoSoftBreaks;
        o.strikethrough_double_tilde = st.extSubSuperscript;
        o.ext_table = st.extTable;
        o.ext_strikethrough = st.extStrikethrough;
        o.ext_autolink = st.extAutolink;
        o.ext_tagfilter = st.extTagFilter;
        o.ext_tasklist = st.extTaskList;
        o.math = st.extMath;
        o.mermaid = st.extMermaid;

        char *htmlC = mq_markdown_to_html(src.UTF8String, &o);
        body = htmlC ? [NSString stringWithUTF8String:htmlC] : @"";
        if (htmlC) free(htmlC);

        if (dlStore.count) body = [self restoreDefinitionLists:body store:dlStore];

        NSMutableArray<NSDictionary *> *headings = [NSMutableArray array];
        if (st.extHeadingAnchors || st.extTableOfContents) {
            body = [self processHeadings:body addIDs:YES headings:headings];
        }
        if (st.extGitHubAlert) body = [self processAlerts:body];
        body = [self inlinePasses:body];
        if (st.extInlineLocalImages && baseDirectory) {
            body = [self inlineLocalImages:body baseDirectory:baseDirectory];
        }
        if (st.extTableOfContents && headings.count >= 3) {
            body = [[self tableOfContents:headings] stringByAppendingString:body];
        }
        body = [frontTable stringByAppendingString:body];

        hasMath = [body containsString:@"class=\"math "];
        hasMermaid = [body containsString:@"class=\"mermaid\""];
        hasCode = [body containsString:@"<code"];
    }

    // -- assemble the document ------------------------------------------
    NSMutableString *doc = [NSMutableString string];
    [doc appendString:@"<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\">\n"];
    [doc appendString:@"<meta name=\"color-scheme\" content=\"light dark\">\n"];
    [doc appendFormat:@"<title>%@</title>\n", [self escapeHTML:sourceName ?: @"Markdown"]];
    [doc appendString:@"<style>\n"];
    [doc appendFormat:@":root{font-size:%.1fpx;}\n", st.baseFontSize];
    [doc appendString:[self themeCSS]];
    if (st.extSyntaxHighlighting && hasCode) [doc appendString:[self highlightThemeCSS]];
    [doc appendString:@"\n</style>\n"];

    NSURL *jsDir = [self.resourceURL URLByAppendingPathComponent:@"js"];
    if (hasMath) {
        // Resources are referenced by absolute file URL so the page works
        // whatever base URL the preview was loaded with. MathJax 4 loads
        // its font from the CDN by default; the loader's `fonts` path is
        // pointed at the bundled @mathjax folder so previews work fully
        // offline and inside the sandbox.
        NSString *mathjax = [[jsDir URLByAppendingPathComponent:@"mathjax/tex-chtml.js"] absoluteString];
        NSString *fontsDir = [[jsDir URLByAppendingPathComponent:@"@mathjax"] absoluteString];
        [doc appendFormat:@"<script>window.MathJax={loader:{paths:{fonts:'%@'}},"
                          @"tex:{inlineMath:[['\\\\(','\\\\)']],displayMath:[['\\\\[','\\\\]']]},"
                          @"options:{enableMenu:false}};</script>\n", fontsDir];
        [doc appendFormat:@"<script async src=\"%@\"></script>\n", mathjax];
    }
    [doc appendString:@"</head><body>\n<article class=\"markdown-body\">\n"];
    [doc appendString:body];
    [doc appendString:@"\n</article>\n"];
    if (st.extSyntaxHighlighting && hasCode) {
        NSString *hljs = [[jsDir URLByAppendingPathComponent:@"highlight/highlight.min.js"] absoluteString];
        [doc appendFormat:@"<script src=\"%@\"></script>\n<script>hljs.highlightAll();</script>\n", hljs];
    }
    if (hasMermaid) {
        NSString *mmd = [[jsDir URLByAppendingPathComponent:@"mermaid/mermaid.min.js"] absoluteString];
        [doc appendFormat:@"<script src=\"%@\"></script>\n", mmd];
        [doc appendString:@"<script>mermaid.initialize({startOnLoad:true,securityLevel:'strict',"
                          @"theme:window.matchMedia('(prefers-color-scheme: dark)').matches?'dark':'default'});</script>\n"];
    }
    [doc appendString:@"</body></html>\n"];
    return doc;
}

@end
