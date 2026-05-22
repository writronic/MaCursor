
#import <getopt.h>
#import "GBCommandLineParser.h"

const struct GBCommandLineKeys {
	__unsafe_unretained NSString *longOption;
	__unsafe_unretained NSString *shortOption;
	__unsafe_unretained NSString *requirement;
	__unsafe_unretained id notAnOption;
} GBCommandLineKeys = {
	.longOption = @"long",
	.shortOption = @"short",
	.requirement = @"requirement",
	.notAnOption = @"not-an-option",
};

#pragma mark -

@interface GBCommandLineParser ()
- (NSDictionary *)optionDataForOption:(NSString *)shortOrLongName value:(NSString **)value;
- (BOOL)isShortOrLongOptionName:(NSString *)value;
@property (nonatomic, strong) NSMutableDictionary *parsedOptions;
@property (nonatomic, strong) NSMutableArray *parsedArguments;
@property (nonatomic, strong) NSMutableDictionary *registeredOptionsByLongNames;
@property (nonatomic, strong) NSMutableDictionary *registeredOptionsByShortNames;
@end

#pragma mark -

@implementation GBCommandLineParser

@synthesize parsedOptions;
@synthesize parsedArguments;
@synthesize registeredOptionsByLongNames;
@synthesize registeredOptionsByShortNames;

#pragma mark - Initialization & disposal

- (id)init {
	self = [super init];
	if (self) {
		self.registeredOptionsByLongNames = [NSMutableDictionary dictionary];
		self.registeredOptionsByShortNames = [NSMutableDictionary dictionary];
		self.parsedOptions = [NSMutableDictionary dictionary];
		self.parsedArguments = [NSMutableArray array];
	}
	return self;
}

#pragma mark - Options registration

- (void)registerOption:(NSString *)longOption shortcut:(char)shortOption requirement:(GBValueRequirements)requirement {
	NSMutableDictionary *data = [NSMutableDictionary dictionary];
	[data setObject:longOption forKey:GBCommandLineKeys.longOption];
	[data setObject:[NSNumber numberWithUnsignedInteger:requirement] forKey:GBCommandLineKeys.requirement];
	if (shortOption > 0) {
		[data setObject:[NSNumber numberWithInt:shortOption] forKey:GBCommandLineKeys.shortOption];
		[self.registeredOptionsByShortNames setObject:data forKey:[NSString stringWithFormat:@"%c", shortOption]];
	}
	[self.registeredOptionsByLongNames setObject:data forKey:longOption];

	if (requirement == GBValueNone) {		
		NSMutableDictionary *negData = [NSMutableDictionary dictionary];
		NSString *negLongOption = [NSString stringWithFormat:@"no-%@", longOption];
		[negData setObject:negLongOption forKey:GBCommandLineKeys.longOption];
		[negData setObject:[NSNumber numberWithUnsignedInteger:requirement] forKey:GBCommandLineKeys.requirement];
		[self.registeredOptionsByLongNames setObject:data forKey:negLongOption];
	}
}

- (void)registerOption:(NSString *)longOption requirement:(GBValueRequirements)requirement {
	[self registerOption:longOption shortcut:0 requirement:requirement];
}

- (void)registerSwitch:(NSString *)longOption shortcut:(char)shortOption {
	[self registerOption:longOption shortcut:shortOption requirement:GBValueNone];
}

- (void)registerSwitch:(NSString *)longOption {
	[self registerSwitch:longOption shortcut:0];
}

#pragma mark - Options parsing

- (BOOL)parseOptionsUsingDefaultArgumentsWithBlock:(GBCommandLineParseBlock)handler {
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    NSString *command = [processInfo processName];
    NSMutableArray *arguments = [[processInfo arguments] mutableCopy];
	[arguments removeObjectAtIndex:0];
	return [self parseOptionsWithArguments:arguments commandLine:command block:handler];
}

- (BOOL)parseOptionsWithArguments:(char **)argv count:(int)argc block:(GBCommandLineParseBlock)handler {
	if (argc == 0) return YES;
	NSString *command = [NSString stringWithUTF8String:argv[0]];
	NSMutableArray *arguments = [NSMutableArray arrayWithCapacity:argc - 1];
	for (int i=1; i<argc; i++) {
		NSString *argument = [NSString stringWithUTF8String:argv[i]];
		[arguments addObject:argument];
	}
	return [self parseOptionsWithArguments:arguments commandLine:command block:handler];
}

- (BOOL)parseOptionsWithArguments:(NSArray *)arguments commandLine:(NSString *)cmd block:(GBCommandLineParseBlock)handler {
	[self.parsedOptions removeAllObjects];
	[self.parsedArguments removeAllObjects];

	BOOL result = YES;
	BOOL stop = NO;
	
	NSUInteger index = 0;
	while (index < arguments.count) {
		id value = nil;
		NSString *input = [arguments objectAtIndex:index];
		NSDictionary *data = [self optionDataForOption:input value:&value];
		if (data == GBCommandLineKeys.notAnOption) break; // no more options, only arguments left...
		
		NSString *name = [data valueForKey:GBCommandLineKeys.longOption];
		GBParseFlags flags = GBParseFlagOption;
		
		if (data == nil) {
			name = input;
			flags = GBParseFlagUnknownOption;
			result = NO;
		} else {
			GBValueRequirements requirement = [[data objectForKey:GBCommandLineKeys.requirement] unsignedIntegerValue];
			switch (requirement) {
				case GBValueRequired:
					if (!value) {
						if (index < arguments.count - 1) {
							value = [arguments objectAtIndex:index + 1];
							if ([self isShortOrLongOptionName:value]) {
								flags = GBParseFlagMissingValue;
							} else {
								index++;
							}
						} else {
							flags = GBParseFlagMissingValue;
						}
					}
					break;
				case GBValueOptional:
					if (!value) {
						if (index < arguments.count - 1) {
							value = [arguments objectAtIndex:index + 1];
							if ([self isShortOrLongOptionName:value]) {
								value = [NSNumber numberWithInt:YES];
							} else {
								index++;
							}
						} else {
							value = [NSNumber numberWithInt:YES];
						}
					}
					break;
				default:
					if ([input hasPrefix:@"--no-"]) {
						if (value) {
							BOOL cmdLineValue = [value boolValue];
							value = [NSNumber numberWithBool:!cmdLineValue];
						} else {
							value = [NSNumber numberWithBool:NO];
						}
					} else {
						if (value) {
							BOOL cmdLineValue = [value boolValue];
							value = [NSNumber numberWithBool:cmdLineValue];
						} else {
							value = [NSNumber numberWithBool:YES];
						}
					}
					break;
			}
		}
		
		handler(flags, name, value, &stop);
		if (stop) return NO;
		
		if (value) [self.parsedOptions setObject:value forKey:name];
		index++;
	}
	
	while (index < arguments.count) {
		NSString *input = [arguments objectAtIndex:index];
		[self.parsedArguments addObject:input];
		handler(GBParseFlagArgument, nil, input, &stop);
		if (stop) return NO;
		index++;
	}
	
	return result;
}

#pragma mark - Helper methods

- (NSDictionary *)optionDataForOption:(NSString *)shortOrLongName value:(NSString **)value {
	NSString *name = nil;
	NSDictionary *options = nil;
	
	if ([shortOrLongName hasPrefix:@"--"]) {
		name = [shortOrLongName substringFromIndex:2];
		options = self.registeredOptionsByLongNames;
	} else if ([shortOrLongName hasPrefix:@"-"]) {
		name = [shortOrLongName substringFromIndex:1];
		options = self.registeredOptionsByShortNames;
	} else {
		return GBCommandLineKeys.notAnOption;
	}
	
	NSRange valueRange = [name rangeOfString:@"=" options:NSBackwardsSearch];
	if (valueRange.location != NSNotFound) {
		if (value) *value = [name substringFromIndex:valueRange.location + 1];
		name = [name substringToIndex:valueRange.location];
	}
	return [options objectForKey:name];
}

- (BOOL)isShortOrLongOptionName:(NSString *)value {
	if ([value hasPrefix:@"--"]) return YES;
	if ([value hasPrefix:@"-"]) return YES;
	return NO;
}

#pragma mark - Getting parsed results

- (id)valueForOption:(NSString *)longOption {
	return [self.parsedOptions objectForKey:longOption];
}

- (NSArray *)arguments {
	return [self.parsedArguments copy];
}

@end
