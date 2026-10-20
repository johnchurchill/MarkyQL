#import <Cocoa/Cocoa.h>
#import "MQAppDelegate.h"

int main(int argc, const char *argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        MQAppDelegate *delegate = [[MQAppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
