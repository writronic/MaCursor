
#import <Foundation/Foundation.h>

@class GBCommandLineParser;
@class GBSettings;

typedef NSUInteger GBOptionFlags;

typedef struct {
	char shortOption;
	__unsafe_unretained NSString *longOption;
	__unsafe_unretained NSString *description;
	GBOptionFlags flags;
} GBOptionDefinition;

typedef NSString *(^GBOptionStringBlock)(void);

#pragma mark - 

@interface GBOptionsHelper : NSObject

#pragma mark - Options registration

- (void)registerOptionsFromDefinitions:(GBOptionDefinition *)definitions;
- (void)registerSeparator:(NSString *)description;
- (void)registerOption:(char)shortName long:(NSString *)longName description:(NSString *)description flags:(GBOptionFlags)flags;

#pragma mark - Integration with other components

- (void)registerOptionsToCommandLineParser:(GBCommandLineParser *)parser;

#pragma mark - Diagnostic info

- (void)printValuesFromSettings:(GBSettings *)settings;
- (void)printVersion;
- (void)printHelp;

#pragma mark - Getting information from user

@property (nonatomic, copy) GBOptionStringBlock applicationName;
@property (nonatomic, copy) GBOptionStringBlock applicationVersion;
@property (nonatomic, copy) GBOptionStringBlock applicationBuild;

#pragma mark - Hooks for injecting text to output

@property (nonatomic, copy) GBOptionStringBlock printValuesHeader;
@property (nonatomic, copy) GBOptionStringBlock printValuesArgumentsHeader;
@property (nonatomic, copy) GBOptionStringBlock printValuesOptionsHeader;
@property (nonatomic, copy) GBOptionStringBlock printValuesFooter;

@property (nonatomic, copy) GBOptionStringBlock printHelpHeader;
@property (nonatomic, copy) GBOptionStringBlock printHelpFooter;

@end

#pragma mark - 

enum {
	GBOptionSeparator = 1 << 3,
	GBOptionNoCmdLine = 1 << 4,
	GBOptionNoPrint = 1 << 5,
	GBOptionNoHelp = 1 << 6,
	GBOptionInvisible = GBOptionNoPrint | GBOptionNoHelp,
};
