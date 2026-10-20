//
//  MQAppDelegate.m
//  MarkyQL — settings app (Objective-C, no nib: the whole UI is built
//  in code so the project builds with a plain Makefile).
//
//  Launching this app is also what registers the Quick Look extension
//  with the system.
//

#import "MQAppDelegate.h"
#import <WebKit/WebKit.h>
#import "MQSettings.h"
#import "MQRenderer.h"

static NSString * const MQSampleMarkdown =
    @"# MarkyQL preview test\n"
    @"\n"
    @"A paragraph with **bold**, *italic*, `inline code`, a [link](https://example.com), "
    @"an emoji shortcode :smile:, ==highlighted text==, and a [[Wikilink]].\n"
    @"\n"
    @"- [x] Task lists work\n"
    @"- [ ] Unchecked item\n"
    @"\n"
    @"| Column A | Column B |\n"
    @"| -------- | -------- |\n"
    @"| Tables   | work     |\n"
    @"\n"
    @"> [!NOTE]\n"
    @"> GitHub alerts render as callouts.\n"
    @"\n"
    @"Term one\n"
    @": Definition lists are supported too.\n"
    @"\n"
    @"```objc\n"
    @"NSString *s = @\"Syntax highlighting\";\n"
    @"```\n"
    @"\n"
    @"Math is **off by default**. Turn it on (left) and this renders: $E = mc^2$\n"
    @"\n"
    @"```mermaid\n"
    @"graph LR\n"
    @"    A[Markdown] --> B[Quick Look]\n"
    @"```\n";

@interface MQAppDelegate () <NSTextFieldDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) MQSettings *settings;
@property (nonatomic, strong) NSURL *currentFile;
@property (nonatomic, strong) NSTextField *fileLabel;
@property (nonatomic, strong) NSPopUpButton *themePopup;
@end

@implementation MQAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.settings = [MQSettings sharedSettings];
    [self buildWindow];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self refreshPreview];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

#pragma mark - UI construction

- (NSButton *)checkbox:(NSString *)title keyPath:(NSString *)keyPath {
    NSButton *b = [NSButton checkboxWithTitle:title target:self action:@selector(toggleChanged:)];
    b.identifier = keyPath;
    b.state = [[self.settings valueForKey:keyPath] boolValue]
        ? NSControlStateValueOn : NSControlStateValueOff;
    return b;
}

- (NSTextField *)label:(NSString *)text bold:(BOOL)bold {
    NSTextField *l = [NSTextField labelWithString:text];
    if (bold) l.font = [NSFont boldSystemFontOfSize:12];
    return l;
}

- (NSTextField *)numberField:(NSString *)identifier value:(double)value width:(CGFloat)width {
    NSTextField *f = [[NSTextField alloc] init];
    f.identifier = identifier;
    f.delegate = self;
    f.doubleValue = value;
    NSNumberFormatter *fmt = [[NSNumberFormatter alloc] init];
    fmt.minimum = @0;
    fmt.maximumFractionDigits = 0;
    f.formatter = fmt;
    [f.widthAnchor constraintEqualToConstant:width].active = YES;
    return f;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 940, 620);
    self.window = [[NSWindow alloc] initWithContentRect:frame
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"MarkyQL Settings";
    self.window.minSize = NSMakeSize(720, 480);
    [self.window center];

    // -- settings form (left) -------------------------------------------
    NSStackView *form = [NSStackView stackViewWithViews:@[]];
    form.orientation = NSUserInterfaceLayoutOrientationVertical;
    form.alignment = NSLayoutAttributeLeading;
    form.spacing = 4;
    form.translatesAutoresizingMaskIntoConstraints = NO;

    [form addArrangedSubview:[self label:@"Extensions" bold:YES]];
    NSArray<NSArray<NSString *> *> *extensions = @[
        @[@"Autolink", @"extAutolink"],
        @[@"Emoji shortcodes", @"extEmoji"],
        @[@"Definition lists", @"extDefinitionList"],
        @[@"GitHub alerts", @"extGitHubAlert"],
        @[@"Heading anchors", @"extHeadingAnchors"],
        @[@"Highlight (==text==)", @"extHighlight"],
        @[@"Inline local images", @"extInlineLocalImages"],
        @[@"Math formulas (MathJax)", @"extMath"],
        @[@"Mermaid diagrams", @"extMermaid"],
        @[@"Strikethrough", @"extStrikethrough"],
        @[@"Sub/superscript (~x~ ^x^)", @"extSubSuperscript"],
        @[@"Syntax highlighting", @"extSyntaxHighlighting"],
        @[@"Tables", @"extTable"],
        @[@"Tag filter (with unsafe HTML)", @"extTagFilter"],
        @[@"Task lists", @"extTaskList"],
        @[@"Wikilinks", @"extWikilinks"],
        @[@"YAML header", @"extYAMLHeader"],
        @[@"Table of contents", @"extTableOfContents"],
    ];
    for (NSArray<NSString *> *pair in extensions) {
        [form addArrangedSubview:[self checkbox:pair[0] keyPath:pair[1]]];
    }
    NSTextField *mathNote = [NSTextField wrappingLabelWithString:
        @"Math is off by default. Off means MathJax is never loaded and "
        @"$ is never treated specially — no exceptions, no surprises."];
    mathNote.font = [NSFont systemFontOfSize:11];
    mathNote.textColor = [NSColor secondaryLabelColor];
    mathNote.preferredMaxLayoutWidth = 300;
    [form addArrangedSubview:mathNote];

    [form addArrangedSubview:[self label:@"Options" bold:YES]];
    NSArray<NSArray<NSString *> *> *options = @[
        @[@"Smart quotes", @"optSmartQuotes"],
        @[@"Footnotes", @"optFootnotes"],
        @[@"Hard breaks", @"optHardBreaks"],
        @[@"No soft breaks", @"optNoSoftBreaks"],
        @[@"Inline HTML (unsafe)", @"optUnsafeHTML"],
        @[@"Validate UTF-8", @"optValidateUTF8"],
        @[@"Render as source code", @"optRenderAsSource"],
    ];
    for (NSArray<NSString *> *pair in options) {
        [form addArrangedSubview:[self checkbox:pair[0] keyPath:pair[1]]];
    }

    [form addArrangedSubview:[self label:@"Appearance" bold:YES]];
    self.themePopup = [[NSPopUpButton alloc] init];
    [self.themePopup addItemsWithTitles:@[@"GitHub theme", @"Custom CSS file…"]];
    self.themePopup.target = self;
    self.themePopup.action = @selector(themeChanged:);
    [self.themePopup selectItemAtIndex:[self.settings.themeName isEqualToString:@"custom"] ? 1 : 0];
    [form addArrangedSubview:self.themePopup];

    NSStackView *fontRow = [NSStackView stackViewWithViews:@[
        [self label:@"Base font size (pt):" bold:NO],
        [self numberField:@"fontSize" value:self.settings.baseFontSize width:52],
    ]];
    [form addArrangedSubview:fontRow];
    NSStackView *widthRow = [NSStackView stackViewWithViews:@[
        [self label:@"Preview width (0 = theme):" bold:NO],
        [self numberField:@"qlWidth" value:self.settings.previewWidth width:52],
    ]];
    [form addArrangedSubview:widthRow];
    NSStackView *heightRow = [NSStackView stackViewWithViews:@[
        [self label:@"Preview height (0 = auto):" bold:NO],
        [self numberField:@"qlHeight" value:self.settings.previewHeight width:52],
    ]];
    [form addArrangedSubview:heightRow];

    NSTextField *foot = [NSTextField wrappingLabelWithString:
        @"Settings save automatically and apply to the next preview. "
        @"MarkyQL adds nothing to your previews: no banners, no counters, "
        @"no donation links. What you see is your document."];
    foot.font = [NSFont systemFontOfSize:11];
    foot.textColor = [NSColor secondaryLabelColor];
    foot.preferredMaxLayoutWidth = 300;
    [form addArrangedSubview:foot];

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.documentView = form;
    [form.widthAnchor constraintEqualToConstant:316].active = YES;
    [form.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor constant:10].active = YES;
    [form.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor constant:10].active = YES;

    // -- preview (right) ---------------------------------------------------
    self.webView = [[WKWebView alloc] init];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;

    NSSplitView *split = [[NSSplitView alloc] init];
    split.vertical = YES;
    split.dividerStyle = NSSplitViewDividerStyleThin;
    split.translatesAutoresizingMaskIntoConstraints = NO;
    [split addSubview:scroll];
    [split addSubview:self.webView];
    [scroll.widthAnchor constraintEqualToConstant:340].active = YES;

    // -- bottom bar ----------------------------------------------------------
    NSButton *openBtn = [NSButton buttonWithTitle:@"Open .md file…" target:self
                                           action:@selector(openFile:)];
    NSButton *sampleBtn = [NSButton buttonWithTitle:@"Sample document" target:self
                                             action:@selector(showSample:)];
    NSButton *qlBtn = [NSButton buttonWithTitle:@"Quick Look settings…" target:self
                                         action:@selector(openQLSettings:)];
    self.fileLabel = [NSTextField labelWithString:@"Sample document"];
    self.fileLabel.textColor = [NSColor secondaryLabelColor];
    NSStackView *bar = [NSStackView stackViewWithViews:@[openBtn, sampleBtn, self.fileLabel, qlBtn]];
    bar.spacing = 8;
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [bar insertView:spacer atIndex:3 inGravity:NSStackViewGravityLeading];

    NSView *content = self.window.contentView;
    [content addSubview:split];
    [content addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [split.topAnchor constraintEqualToAnchor:content.topAnchor],
        [split.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [split.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [split.bottomAnchor constraintEqualToAnchor:bar.topAnchor constant:-6],
        [bar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:10],
        [bar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-10],
        [bar.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-8],
    ]];
}

#pragma mark - actions

- (void)toggleChanged:(NSButton *)sender {
    [self.settings setValue:@(sender.state == NSControlStateValueOn) forKey:sender.identifier];
    // Hard breaks / no soft breaks clear each other in the model;
    // refresh both checkboxes if one of them changed.
    if ([sender.identifier hasPrefix:@"optHard"] || [sender.identifier hasPrefix:@"optNoSoft"]) {
        [self.window.contentView setNeedsDisplay:YES];
    }
    [self refreshPreview];
}

- (void)themeChanged:(NSPopUpButton *)sender {
    if (sender.indexOfSelectedItem == 0) {
        self.settings.themeName = @"github";
        [self refreshPreview];
        return;
    }
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[@"css"];
    panel.message = @"Choose a CSS theme file";
    if ([panel runModal] == NSModalResponseOK) {
        self.settings.themeName = @"custom";
        self.settings.customCSSPath = panel.URL.path;
    } else {
        [sender selectItemAtIndex:0];
        self.settings.themeName = @"github";
    }
    [self refreshPreview];
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
    NSTextField *f = note.object;
    if ([f.identifier isEqualToString:@"fontSize"]) {
        double v = f.doubleValue;
        if (v >= 6 && v <= 72) self.settings.baseFontSize = v;
    } else if ([f.identifier isEqualToString:@"qlWidth"]) {
        self.settings.previewWidth = f.doubleValue;
    } else if ([f.identifier isEqualToString:@"qlHeight"]) {
        self.settings.previewHeight = f.doubleValue;
    }
    [self refreshPreview];
}

- (void)openFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[@"md", @"markdown", @"mdown", @"rmd", @"mdx", @"qmd", @"apib", @"mermaid"];
    if ([panel runModal] == NSModalResponseOK) {
        self.currentFile = panel.URL;
        self.fileLabel.stringValue = panel.URL.lastPathComponent;
        [self refreshPreview];
    }
}

- (void)showSample:(id)sender {
    self.currentFile = nil;
    self.fileLabel.stringValue = @"Sample document";
    [self refreshPreview];
}

- (void)openQLSettings:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:
        [NSURL URLWithString:@"x-apple.systempreferences:com.apple.LoginItems-Settings"]];
}

#pragma mark - preview

- (void)refreshPreview {
    MQRenderer *renderer = [[MQRenderer alloc]
        initWithResourceURL:[NSBundle mainBundle].resourceURL
                   settings:self.settings];
    NSString *html = nil;
    if (self.currentFile) {
        html = [renderer renderFileAtURL:self.currentFile error:nil];
    } else {
        html = [renderer renderMarkdown:MQSampleMarkdown
                             sourceName:@"Sample.md"
                          baseDirectory:nil];
    }
    if (html) {
        NSURL *base = self.currentFile
            ? [MQRenderer resolveMarkdownFileURL:self.currentFile].URLByDeletingLastPathComponent
            : [NSBundle mainBundle].resourceURL;
        [self.webView loadHTMLString:html baseURL:base];
    }
}

@end
