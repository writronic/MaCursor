#import "MCDefs.h"
#import "restore.h"
#import "apply.h"
#import "create.h"
#import "listen.h"
#import "scale.h"

#import <GBCli/GBSettings.h>
#import <GBCli/GBOptionsHelper.h>
#import <GBCli/GBCommandLineParser.h>

@interface GBOptionsHelper (Helper)
- (void)replacePlaceholdersAndPrintStringFromBlock:(GBOptionStringBlock)block;
@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        GBSettings *settings = [GBSettings settingsWithName:@"macursor" parent:nil];
        
        GBOptionsHelper *options = [[GBOptionsHelper alloc] init];
        [options registerSeparator:@(BOLD "APPLYING CURSOR THEMES" RESET)];
        [options registerOption:'a' long:@"apply" description:@"Apply a cursor theme" flags:GBValueRequired];
        [options registerOption:'r' long:@"reset" description:@"Reset to the default OSX cursors" flags:GBValueNone];
        [options registerSeparator:@(BOLD "CREATING CURSOR THEMES" RESET)];
        [options registerOption:'c' long:@"create"
                    description:
         @"Create a cursor from a folder. Default output is to a new file of the same name. Directory must use the format:\n"
         "\t\t├── com.apple.coregraphics.Arrow\n"
         "\t\t│   ├── 0.png\n"
         "\t\t│   ├── 1.png\n"
         "\t\t│   ├── 2.png\n"
         "\t\t│   └── 3.png\n"
         "\t\t├── com.apple.coregraphics.Wait\n"
         "\t\t│   ├── 0.png\n"
         "\t\t│   ├── 1.png\n"
         "\t\t│   └── 2.png\n"
         "\t\t├── com.apple.cursor.3\n"
         "\t\t│   ├── 0.png\n"
         "\t\t│   ├── 1.png\n"
         "\t\t│   ├── 2.png\n"
         "\t\t│   └── 3.png\n"
         "\t\t└── com.apple.cursor.5\n"
         "\t\t    ├── 0.png\n"
         "\t\t    ├── 1.png\n"
         "\t\t    ├── 2.png\n"
         "\t\t    └── 3.png\n"
                          flags:GBValueRequired];
        [options registerOption:'d' long:@"dump" description:@"Dumps the currently applied cursors to a file." flags:GBValueRequired];
        [options registerOption:0 long:@"capture-defaults" description:@"Capture system default cursors to a .cursor file" flags:GBValueRequired | GBOptionNoHelp | GBOptionNoPrint];
        [options registerSeparator:@(BOLD "MISCELLANEOUS" RESET)];
        [options registerOption:'e' long:@"export" description:@"Export a cursor theme to a directory" flags:GBValueRequired];
        [options registerOption:'?' long:@"help" description:@"Display this help and exit" flags:GBValueNone];
        [options registerOption:'o' long:@"output" description:@"Use this option to tell where an output file goes. (For create and export)" flags:GBValueRequired];
        [options registerOption:0 long:@"suppressCopyright" description:@"Suppress Copyright info" flags:GBValueNone | GBOptionNoHelp | GBOptionNoPrint];
        [options registerOption:'s' long:@"scale" description:@"Scale the cursor to obscene multipliers or get the current scale" flags:GBValueOptional];
        [options registerOption:0 long:@"listen" description:@"Keep mousecloak alive to apply the current Cursor Theme every user switch" flags:GBValueNone | GBOptionNoHelp | GBOptionNoPrint];
        
        options.applicationName = ^{ return @"mousecloak"; };
        options.applicationVersion = ^{ return @"2.0"; };
        options.applicationBuild = ^{ return @""; };
        options.printHelpHeader = ^{ return @(BOLD WHITE "%APPNAME v%APPVERSION" RESET); };
        options.printHelpFooter = ^{ return @(BOLD WHITE "Copyright © 2026 Writronic. All rights reserved." RESET); };
        
        GBCommandLineParser *parser = [[GBCommandLineParser alloc] init];
        [options registerOptionsToCommandLineParser:parser];
        [parser parseOptionsWithArguments:argv count:argc block:^(GBParseFlags flags, NSString *option, id value, BOOL *stop) {
            switch (flags) {
                case GBParseFlagUnknownOption:
                    MMLog(BOLD RED "Unknown command line option %s, try --help!" RESET, option.UTF8String);
                    break;
                case GBParseFlagMissingValue:
                    MMLog(BOLD RED "Missing value for command line option %s, try --help!" RESET, option.UTF8String);
                    break;
                case GBParseFlagArgument:
                    [settings setObject:@YES forKey:value];
                    break;
                case GBParseFlagOption:
                    [settings setObject:value forKey:option];
                    break;
            }
        }];
        
        if ([settings boolForKey:@"help"] || argc == 1) {
            [options printHelp];
            return EXIT_SUCCESS;
        }
        
        BOOL suppressCopyright = [settings boolForKey:@"suppressCopyright"];
        
        if (!suppressCopyright)
            [options replacePlaceholdersAndPrintStringFromBlock:options.printHelpHeader];
        
        if ([settings boolForKey:@"reset"]) {
            resetAllCursors(NULL);
            
            if (!suppressCopyright)
                [options replacePlaceholdersAndPrintStringFromBlock:options.printHelpFooter];
            return EXIT_SUCCESS;
        }
        
        BOOL apply           = [settings isKeyPresentAtThisLevel:@"apply"];
        BOOL create          = [settings isKeyPresentAtThisLevel:@"create"];
        BOOL dump            = [settings isKeyPresentAtThisLevel:@"dump"];
        BOOL captureDefaults = [settings isKeyPresentAtThisLevel:@"capture-defaults"];
        BOOL scale           = [settings isKeyPresentAtThisLevel:@"scale"];
        BOOL listen          = [settings isKeyPresentAtThisLevel:@"listen"];
        BOOL export          = [settings isKeyPresentAtThisLevel:@"export"];
        int amt = 0;
        
        if (apply) amt++;
        if (create) amt++;
        if (dump) amt++;
        if (captureDefaults) amt++;
        if (scale) amt++;
        if (listen) amt++;
        if (export) amt++;
        
        if (amt > 1) {
            MMLog(BOLD RED "One command at a time, son!" RESET);
            
            if (!suppressCopyright)
                [options replacePlaceholdersAndPrintStringFromBlock:options.printHelpFooter];
            return 0;
        }
        
        if (apply) {
            applyThemeAtPath([settings objectForKey:@"apply"]);
        } else if (create) {
            NSError *error  = nil;
            NSString *input = [settings objectForKey:@"create"];
            NSString *output = [settings isKeyPresentAtThisLevel:@"output"] ? [settings objectForKey:@"output"] : input.stringByDeletingLastPathComponent;
            
            error = createCursorTheme(input, output);
            if (error) {
                MMLog(BOLD RED "%s" RESET, error.localizedDescription.UTF8String);
            } else {
                MMLog(BOLD GREEN "Cursor theme successfully written to %s" RESET, output.UTF8String);
            }
        } else if (export) {
            NSString *input = [settings objectForKey:@"export"];
            NSString *output = [settings isKeyPresentAtThisLevel:@"output"] ? [settings objectForKey:@"output"] : nil;
            if (!output) {
                MMLog(BOLD RED "You must specify an output directory with -o!" RESET);
            } else {
                NSData *exportData = [NSData dataWithContentsOfFile:input options:0 error:nil];
                NSDictionary *exportTheme = exportData ? [NSPropertyListSerialization propertyListWithData:exportData options:NSPropertyListImmutable format:NULL error:nil] : nil;
                if (exportTheme) {
                    exportCursorTheme(exportTheme, output);
                } else {
                    MMLog(BOLD RED "Could not read valid plist at %s" RESET, input.UTF8String);
                }
            }
        } else if (dump) {
            dumpCursorsToFile([settings objectForKey:@"dump"], ^BOOL (NSUInteger progress, NSUInteger total) {
                MMLog("Dumped %lu of %lu", (unsigned long)progress, (unsigned long)total);
                return YES;
            });
        } else if (captureDefaults) {
            NSString *outputPath = [settings objectForKey:@"capture-defaults"];
            BOOL ok = MCPerformCursorCapture(outputPath);
            if (!suppressCopyright)
                [options replacePlaceholdersAndPrintStringFromBlock:options.printHelpFooter];
            return ok ? EXIT_SUCCESS : EXIT_FAILURE;
        } else if (scale) {
            NSNumber *number = [settings objectForKey:@"scale"];
            
            if (argc == 2) {
                MMLog("%f", cursorScale());
            } else {
                float dbl = number.floatValue;
                setCursorScale(dbl);
            }
        } else if (listen) {
            listener();
        }

        if (!suppressCopyright)
            [options replacePlaceholdersAndPrintStringFromBlock:options.printHelpFooter];
        
        return EXIT_SUCCESS;
    }
}
