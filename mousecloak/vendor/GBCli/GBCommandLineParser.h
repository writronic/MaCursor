
#import <Foundation/Foundation.h>

typedef NSUInteger GBValueRequirements;
typedef NSUInteger GBParseFlags;
typedef void(^GBCommandLineParseBlock)(GBParseFlags flags, NSString *argument, id value, BOOL *stop);

@interface GBCommandLineParser : NSObject

#pragma mark - Options registration

- (void)registerOption:(NSString *)longOption shortcut:(char)shortOption requirement:(GBValueRequirements)requirement;
- (void)registerOption:(NSString *)longOption requirement:(GBValueRequirements)requirement;
- (void)registerSwitch:(NSString *)longOption shortcut:(char)shortOption;
- (void)registerSwitch:(NSString *)longOption;

#pragma mark - Options parsing

- (BOOL)parseOptionsUsingDefaultArgumentsWithBlock:(GBCommandLineParseBlock)handler;
- (BOOL)parseOptionsWithArguments:(char **)argv count:(int)argc block:(GBCommandLineParseBlock)handler;
- (BOOL)parseOptionsWithArguments:(NSArray *)arguments commandLine:(NSString *)cmd block:(GBCommandLineParseBlock)handler;

#pragma mark - Getting parsed results

- (id)valueForOption:(NSString *)longOption;
- (NSArray *)arguments;

@end

#pragma mark -

enum {
	GBValueRequired,
	GBValueOptional,
	GBValueNone
};

enum {
	GBParseFlagOption,
	GBParseFlagArgument,
	GBParseFlagMissingValue,
	GBParseFlagUnknownOption,
};
