//
//  MQSettings.m
//  MarkyQL
//

#import "MQSettings.h"

NSString * const MQAppGroupIdentifier = @"group.com.markyql.shared";

@interface MQSettings ()
@property (nonatomic, strong) NSUserDefaults *defaults;
@end

@implementation MQSettings

+ (instancetype)sharedSettings {
    static MQSettings *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    NSUserDefaults *suite = [[NSUserDefaults alloc] initWithSuiteName:MQAppGroupIdentifier];
    // If the app group is unavailable (e.g. an unsigned local build),
    // fall back to standard defaults rather than failing outright.
    return [self initWithDefaults:suite ?: [NSUserDefaults standardUserDefaults]];
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (self) {
        _defaults = defaults;
        [_defaults registerDefaults:@{
            @"mq.ext.autolink": @YES,
            @"mq.ext.emoji": @YES,
            @"mq.ext.definitionList": @YES,
            @"mq.ext.gitHubAlert": @YES,
            @"mq.ext.headingAnchors": @YES,
            @"mq.ext.highlight": @YES,
            @"mq.ext.inlineLocalImages": @YES,
            @"mq.ext.math": @NO,            // off by default, opt in
            @"mq.ext.mermaid": @YES,
            @"mq.ext.strikethrough": @YES,
            @"mq.ext.subSuperscript": @NO,  // conflicts with single-tilde strikethrough
            @"mq.ext.syntaxHighlighting": @YES,
            @"mq.ext.table": @YES,
            @"mq.ext.tagFilter": @YES,
            @"mq.ext.taskList": @YES,
            @"mq.ext.wikilinks": @YES,
            @"mq.ext.yamlHeader": @YES,
            @"mq.ext.tableOfContents": @NO,
            @"mq.opt.smartQuotes": @NO,
            @"mq.opt.footnotes": @YES,
            @"mq.opt.hardBreaks": @NO,
            @"mq.opt.noSoftBreaks": @NO,
            @"mq.opt.unsafeHTML": @NO,
            @"mq.opt.validateUTF8": @YES,
            @"mq.opt.renderAsSource": @NO,
            @"mq.theme.name": @"github",
            @"mq.theme.baseFontSize": @14.0,
            @"mq.preview.width": @0.0,
            @"mq.preview.height": @0.0,
        }];
    }
    return self;
}

- (void)reload {
    [self.defaults synchronize];
}

#pragma mark - bool accessors

#define MQ_BOOL_PROPERTY(NAME, SETTER, KEY)                                \
    - (BOOL)NAME { return [self.defaults boolForKey:KEY]; }               \
    - (void)set##SETTER:(BOOL)value {                                      \
        [self.defaults setBool:value forKey:KEY];                          \
        [self.defaults synchronize];                                       \
    }

MQ_BOOL_PROPERTY(extAutolink, ExtAutolink, @"mq.ext.autolink")
MQ_BOOL_PROPERTY(extEmoji, ExtEmoji, @"mq.ext.emoji")
MQ_BOOL_PROPERTY(extDefinitionList, ExtDefinitionList, @"mq.ext.definitionList")
MQ_BOOL_PROPERTY(extGitHubAlert, ExtGitHubAlert, @"mq.ext.gitHubAlert")
MQ_BOOL_PROPERTY(extHeadingAnchors, ExtHeadingAnchors, @"mq.ext.headingAnchors")
MQ_BOOL_PROPERTY(extHighlight, ExtHighlight, @"mq.ext.highlight")
MQ_BOOL_PROPERTY(extInlineLocalImages, ExtInlineLocalImages, @"mq.ext.inlineLocalImages")
MQ_BOOL_PROPERTY(extMath, ExtMath, @"mq.ext.math")
MQ_BOOL_PROPERTY(extMermaid, ExtMermaid, @"mq.ext.mermaid")
MQ_BOOL_PROPERTY(extStrikethrough, ExtStrikethrough, @"mq.ext.strikethrough")
MQ_BOOL_PROPERTY(extSubSuperscript, ExtSubSuperscript, @"mq.ext.subSuperscript")
MQ_BOOL_PROPERTY(extSyntaxHighlighting, ExtSyntaxHighlighting, @"mq.ext.syntaxHighlighting")
MQ_BOOL_PROPERTY(extTable, ExtTable, @"mq.ext.table")
MQ_BOOL_PROPERTY(extTagFilter, ExtTagFilter, @"mq.ext.tagFilter")
MQ_BOOL_PROPERTY(extTaskList, ExtTaskList, @"mq.ext.taskList")
MQ_BOOL_PROPERTY(extWikilinks, ExtWikilinks, @"mq.ext.wikilinks")
MQ_BOOL_PROPERTY(extYAMLHeader, ExtYAMLHeader, @"mq.ext.yamlHeader")
MQ_BOOL_PROPERTY(extTableOfContents, ExtTableOfContents, @"mq.ext.tableOfContents")

MQ_BOOL_PROPERTY(optSmartQuotes, OptSmartQuotes, @"mq.opt.smartQuotes")
MQ_BOOL_PROPERTY(optFootnotes, OptFootnotes, @"mq.opt.footnotes")
MQ_BOOL_PROPERTY(optUnsafeHTML, OptUnsafeHTML, @"mq.opt.unsafeHTML")
MQ_BOOL_PROPERTY(optValidateUTF8, OptValidateUTF8, @"mq.opt.validateUTF8")
MQ_BOOL_PROPERTY(optRenderAsSource, OptRenderAsSource, @"mq.opt.renderAsSource")

// Hard breaks and no-soft-breaks are mutually exclusive.
- (BOOL)optHardBreaks { return [self.defaults boolForKey:@"mq.opt.hardBreaks"]; }
- (void)setOptHardBreaks:(BOOL)value {
    [self.defaults setBool:value forKey:@"mq.opt.hardBreaks"];
    if (value) [self.defaults setBool:NO forKey:@"mq.opt.noSoftBreaks"];
    [self.defaults synchronize];
}
- (BOOL)optNoSoftBreaks { return [self.defaults boolForKey:@"mq.opt.noSoftBreaks"]; }
- (void)setOptNoSoftBreaks:(BOOL)value {
    [self.defaults setBool:value forKey:@"mq.opt.noSoftBreaks"];
    if (value) [self.defaults setBool:NO forKey:@"mq.opt.hardBreaks"];
    [self.defaults synchronize];
}

#pragma mark - appearance

- (NSString *)themeName { return [self.defaults stringForKey:@"mq.theme.name"] ?: @"github"; }
- (void)setThemeName:(NSString *)value {
    [self.defaults setObject:value ?: @"github" forKey:@"mq.theme.name"];
    [self.defaults synchronize];
}
- (NSString *)customCSSPath { return [self.defaults stringForKey:@"mq.theme.customCSSPath"]; }
- (void)setCustomCSSPath:(NSString *)value {
    if (value) [self.defaults setObject:value forKey:@"mq.theme.customCSSPath"];
    else [self.defaults removeObjectForKey:@"mq.theme.customCSSPath"];
    [self.defaults synchronize];
}
- (double)baseFontSize { return [self.defaults doubleForKey:@"mq.theme.baseFontSize"]; }
- (void)setBaseFontSize:(double)value {
    [self.defaults setDouble:value forKey:@"mq.theme.baseFontSize"];
    [self.defaults synchronize];
}
- (double)previewWidth { return [self.defaults doubleForKey:@"mq.preview.width"]; }
- (void)setPreviewWidth:(double)value {
    [self.defaults setDouble:value forKey:@"mq.preview.width"];
    [self.defaults synchronize];
}
- (double)previewHeight { return [self.defaults doubleForKey:@"mq.preview.height"]; }
- (void)setPreviewHeight:(double)value {
    [self.defaults setDouble:value forKey:@"mq.preview.height"];
    [self.defaults synchronize];
}

@end
