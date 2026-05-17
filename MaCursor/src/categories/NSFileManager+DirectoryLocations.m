#import "NSFileManager+DirectoryLocations.h"

enum
{
	DirectoryLocationErrorNoPathFound,
	DirectoryLocationErrorFileExistsAtLocation
};
	
NSString * const DirectoryLocationDomain = @"DirectoryLocationDomain";

@implementation NSFileManager (DirectoryLocations)

- (NSString *)findOrCreateDirectory:(NSSearchPathDirectory)searchPathDirectory
	inDomain:(NSSearchPathDomainMask)domainMask
	appendPathComponent:(NSString *)appendComponent
	error:(NSError **)errorOut
{
	NSArray* paths = NSSearchPathForDirectoriesInDomains(
		searchPathDirectory,
		domainMask,
		YES);
	if ([paths count] == 0)
	{
		if (errorOut)
		{
			NSDictionary *userInfo =
				[NSDictionary dictionaryWithObjectsAndKeys:
					NSLocalizedStringFromTable(
						@"No path found for directory in domain.",
						@"Errors",
					nil),
					NSLocalizedDescriptionKey,
					[NSNumber numberWithInteger:searchPathDirectory],
					@"NSSearchPathDirectory",
					[NSNumber numberWithInteger:domainMask],
					@"NSSearchPathDomainMask",
				nil];
			*errorOut =
				[NSError 
					errorWithDomain:DirectoryLocationDomain
					code:DirectoryLocationErrorNoPathFound
					userInfo:userInfo];
		}
		return nil;
	}
	
	NSString *resolvedPath = [paths objectAtIndex:0];

	if (appendComponent)
	{
		resolvedPath = [resolvedPath
			stringByAppendingPathComponent:appendComponent];
	}
	
	NSError *error = nil;
	BOOL success = [self
		createDirectoryAtPath:resolvedPath
		withIntermediateDirectories:YES
		attributes:nil
		error:&error];
	if (!success) 
	{
		if (errorOut)
		{
			*errorOut = error;
		}
		return nil;
	}
	
	if (errorOut)
	{
		*errorOut = nil;
	}
	return resolvedPath;
}

- (NSString *)applicationSupportDirectory
{
	NSString *executableName =
		[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleExecutable"];
	NSError *error;
	NSString *result =
		[self
			findOrCreateDirectory:NSApplicationSupportDirectory
			inDomain:NSUserDomainMask
			appendPathComponent:executableName
			error:&error];
	if (!result)
	{
		NSLog(@"Unable to find or create application support directory:\n%@", error);
	}
	return result;
}

@end
