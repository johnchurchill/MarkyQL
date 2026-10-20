//
//  MQSettings.h
//  MarkyQL
//
//  Shared settings for the app, the Quick Look extension and the CLI.
//  Stored in the app-group UserDefaults suite so all three processes
//  read the same values. Every feature is a real toggle: turning one
//  off removes both its markup and its JavaScript from the output.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// App-group suite shared by the app and the Quick Look extension.
extern NSString * const MQAppGroupIdentifier;

@interface MQSettings : NSObject

+ (instancetype)sharedSettings;

/// Designated initializer with an explicit defaults store.
/// The CLI uses this to layer one-off flag overrides over the shared
/// settings without persisting them.
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;

/// Re-read from disk. The extension calls this on every preview so
/// changes made in the app apply without restarting anything.
- (void)reload;

// -- Extensions ------------------------------------------------------------
@property (nonatomic) BOOL extAutolink;
@property (nonatomic) BOOL extEmoji;
@property (nonatomic) BOOL extDefinitionList;
@property (nonatomic) BOOL extGitHubAlert;
@property (nonatomic) BOOL extHeadingAnchors;
@property (nonatomic) BOOL extHighlight;          // ==text==
@property (nonatomic) BOOL extInlineLocalImages;
@property (nonatomic) BOOL extMath;               // default OFF: no MathJax, no $ parsing
@property (nonatomic) BOOL extMermaid;
@property (nonatomic) BOOL extStrikethrough;
@property (nonatomic) BOOL extSubSuperscript;     // ~sub~ and ^sup^
@property (nonatomic) BOOL extSyntaxHighlighting;
@property (nonatomic) BOOL extTable;
@property (nonatomic) BOOL extTagFilter;          // only matters with unsafe HTML
@property (nonatomic) BOOL extTaskList;
@property (nonatomic) BOOL extWikilinks;
@property (nonatomic) BOOL extYAMLHeader;
@property (nonatomic) BOOL extTableOfContents;

// -- Parser / render options ------------------------------------------------
@property (nonatomic) BOOL optSmartQuotes;
@property (nonatomic) BOOL optFootnotes;
@property (nonatomic) BOOL optHardBreaks;
@property (nonatomic) BOOL optNoSoftBreaks;
@property (nonatomic) BOOL optUnsafeHTML;
@property (nonatomic) BOOL optValidateUTF8;
@property (nonatomic) BOOL optRenderAsSource;

// -- Appearance --------------------------------------------------------------
@property (nonatomic, copy) NSString *themeName;          // "github" or "custom"
@property (nonatomic, copy, nullable) NSString *customCSSPath;
@property (nonatomic) double baseFontSize;                // points, used as 1rem
@property (nonatomic) double previewWidth;                // 0 = derive from theme
@property (nonatomic) double previewHeight;               // 0 = theme default

@end

NS_ASSUME_NONNULL_END
