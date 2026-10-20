//
//  MQRenderer.h
//  MarkyQL
//
//  Turns a markdown file into a complete, self-contained HTML document:
//  cmark-gfm for the core, MarkyQL post-processing for the extension
//  features cmark-gfm does not have (alerts, ==highlight==, wikilinks,
//  emoji, sub/superscript, heading anchors, definition lists, TOC),
//  local image inlining, theme CSS, and conditional MathJax / Mermaid /
//  highlight.js injection. A feature that is off emits nothing at all.
//

#import <Foundation/Foundation.h>
#import "MQSettings.h"

NS_ASSUME_NONNULL_BEGIN

@interface MQRenderer : NSObject

/// resourceURL is the folder holding `themes/` and `js/`
/// (the app bundle's Resources folder for the app and extension).
- (instancetype)initWithResourceURL:(NSURL *)resourceURL settings:(MQSettings *)settings;

/// If the URL is a textbundle package, returns the markdown file inside
/// it; otherwise returns the URL itself.
+ (NSURL *)resolveMarkdownFileURL:(NSURL *)url;

/// Full HTML document for a markdown file.
- (nullable NSString *)renderFileAtURL:(NSURL *)url error:(NSError **)error;

/// Full HTML document for markdown source text. baseDirectory is used to
/// resolve relative image paths for inlining.
- (NSString *)renderMarkdown:(NSString *)source
                 sourceName:(NSString *)sourceName
              baseDirectory:(nullable NSURL *)baseDirectory;

/// Suggested Quick Look content size derived from the settings and the
/// theme's --content-max-width (the caller caps it to the screen).
- (CGSize)preferredPreviewSize;

@end

NS_ASSUME_NONNULL_END
