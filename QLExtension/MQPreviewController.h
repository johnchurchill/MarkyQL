//
//  MQPreviewController.h
//  MarkyQL — Quick Look preview extension (Objective-C)
//

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import <WebKit/WebKit.h>

@interface MQPreviewController : NSViewController <QLPreviewingController, WKNavigationDelegate>
@end
