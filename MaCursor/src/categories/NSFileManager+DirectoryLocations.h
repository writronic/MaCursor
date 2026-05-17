#import <Foundation/Foundation.h>

@interface NSFileManager (DirectoryLocations)

- (NSString *)findOrCreateDirectory:(NSSearchPathDirectory)searchPathDirectory
	inDomain:(NSSearchPathDomainMask)domainMask
	appendPathComponent:(NSString *)appendComponent
	error:(NSError **)errorOut;
- (NSString *)applicationSupportDirectory;

@end
