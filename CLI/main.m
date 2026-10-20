//
//  main.m — markyql CLI
//  MarkyQL
//
//  Renders a markdown file to a complete HTML document on stdout,
//  using the same pipeline and the same shared settings as the
//  Quick Look extension. Flags layer one-off overrides over the
//  saved settings without changing them.
//
//  Usage: markyql <file.md> [-o out.html] [--resources dir]
//                 [--math|--no-math] [--mermaid|--no-mermaid]
//                 [--emoji|--no-emoji] [--source]
//

#import <Foundation/Foundation.h>
#import "MQSettings.h"
#import "MQRenderer.h"

static void usage(void) {
    fprintf(stderr,
        "usage: markyql <file.md> [-o out.html] [--resources dir]\n"
        "               [--math|--no-math] [--mermaid|--no-mermaid]\n"
        "               [--emoji|--no-emoji] [--source]\n");
}

static NSURL *defaultResourcesURL(void) {
    NSString *env = NSProcessInfo.processInfo.environment[@"MARKYQL_RESOURCES"];
    if (env) return [NSURL fileURLWithPath:env];
    // Inside MarkyQL.app/Contents/MacOS: resources are one level up.
    NSURL *exe = [NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments.firstObject];
    NSURL *sibling = [[exe.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent
        URLByAppendingPathComponent:@"Resources"] URLByStandardizingPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[sibling URLByAppendingPathComponent:@"themes"].path]) {
        return sibling;
    }
    NSURL *installed = [NSURL fileURLWithPath:@"/Applications/MarkyQL.app/Contents/Resources"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:installed.path]) return installed;
    return [NSURL fileURLWithPath:@"Resources"];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *input = nil, *output = nil;
        NSURL *resources = nil;
        NSMutableDictionary *overrides = [NSMutableDictionary dictionary];

        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"-o"] && i + 1 < argc) {
                output = [NSString stringWithUTF8String:argv[++i]];
            } else if ([arg isEqualToString:@"--resources"] && i + 1 < argc) {
                resources = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[++i]]];
            } else if ([arg isEqualToString:@"--math"]) {
                overrides[@"mq.ext.math"] = @YES;
            } else if ([arg isEqualToString:@"--no-math"]) {
                overrides[@"mq.ext.math"] = @NO;
            } else if ([arg isEqualToString:@"--mermaid"]) {
                overrides[@"mq.ext.mermaid"] = @YES;
            } else if ([arg isEqualToString:@"--no-mermaid"]) {
                overrides[@"mq.ext.mermaid"] = @NO;
            } else if ([arg isEqualToString:@"--emoji"]) {
                overrides[@"mq.ext.emoji"] = @YES;
            } else if ([arg isEqualToString:@"--no-emoji"]) {
                overrides[@"mq.ext.emoji"] = @NO;
            } else if ([arg isEqualToString:@"--source"]) {
                overrides[@"mq.opt.renderAsSource"] = @YES;
            } else if ([arg hasPrefix:@"-"]) {
                usage();
                return 2;
            } else if (!input) {
                input = arg;
            }
        }
        if (!input) { usage(); return 2; }

        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:MQAppGroupIdentifier]
            ?: [NSUserDefaults standardUserDefaults];
        if (overrides.count) {
            [defaults setVolatileDomain:overrides forName:@"com.markyql.cli-overrides"];
        }
        MQSettings *settings = [[MQSettings alloc] initWithDefaults:defaults];
        MQRenderer *renderer = [[MQRenderer alloc]
            initWithResourceURL:resources ?: defaultResourcesURL()
                       settings:settings];

        NSError *error = nil;
        NSString *html = [renderer renderFileAtURL:[NSURL fileURLWithPath:input] error:&error];
        if (!html) {
            fprintf(stderr, "markyql: %s\n", error.localizedDescription.UTF8String ?: "render failed");
            return 1;
        }
        if (output) {
            [html writeToFile:output atomically:YES encoding:NSUTF8StringEncoding error:&error];
            if (error) {
                fprintf(stderr, "markyql: %s\n", error.localizedDescription.UTF8String);
                return 1;
            }
        } else {
            printf("%s", html.UTF8String);
        }
        return 0;
    }
}
