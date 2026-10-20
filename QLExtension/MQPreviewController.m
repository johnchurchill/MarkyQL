//
//  MQPreviewController.m
//  MarkyQL — Quick Look preview extension (Objective-C)
//
//  View-based preview: render the file to a full HTML document with
//  MQRenderer and show it in a WKWebView. Nothing is ever added to the
//  rendered output — no banners, no footers, no counters.
//

#import "MQPreviewController.h"
#import "MQRenderer.h"
#import "MQSettings.h"

@implementation MQPreviewController {
    WKWebView *_webView;
}

- (void)loadView {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    _webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:config];
    _webView.navigationDelegate = self;
    self.view = _webView;
}

- (void)preparePreviewOfFileAtURL:(NSURL *)url
                completionHandler:(void (^)(NSError * _Nullable))handler {
    MQSettings *settings = [MQSettings sharedSettings];
    [settings reload];

    // Resources (themes + js) are copied into the appex bundle itself.
    MQRenderer *renderer = [[MQRenderer alloc]
        initWithResourceURL:[NSBundle mainBundle].resourceURL
                   settings:settings];

    NSError *error = nil;
    NSString *html = [renderer renderFileAtURL:url error:&error];
    if (!html) {
        handler(error ?: [NSError errorWithDomain:@"com.markyql.preview" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"Could not read the file."}]);
        return;
    }

    // Suggest a content size from the theme/settings, capped to the
    // screen the way QLMarkdown does it.
    CGSize size = [renderer preferredPreviewSize];
    NSScreen *screen = [NSScreen mainScreen];
    if (screen) {
        NSSize avail = screen.visibleFrame.size;
        size.width = MIN(size.width, avail.width * 0.9);
        size.height = MIN(size.height, avail.height * 0.9);
    }
    self.preferredContentSize = NSMakeSize(size.width, size.height);

    NSURL *mdURL = [MQRenderer resolveMarkdownFileURL:url];
    [_webView loadHTMLString:html
                     baseURL:mdURL.URLByDeletingLastPathComponent];
    handler(nil);
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
        NSURL *target = navigationAction.request.URL;
        NSString *scheme = target.scheme.lowercaseString;
        if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] ||
            [scheme isEqualToString:@"mailto"]) {
            [[NSWorkspace sharedWorkspace] openURL:target];
        }
        // All link clicks stay inside the user's browser, never navigate
        // the preview itself. (In-preview .md navigation is a roadmap item.)
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (WKWebView *)webView:(WKWebView *)webView
    createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
       forNavigationAction:(WKNavigationAction *)navigationAction
            windowFeatures:(WKWindowFeatures *)windowFeatures {
    NSURL *target = navigationAction.request.URL;
    if (target) [[NSWorkspace sharedWorkspace] openURL:target];
    return nil;
}

@end
