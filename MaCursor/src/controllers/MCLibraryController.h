#import <Foundation/Foundation.h>
#import "MCCursorLibrary.h"

@interface MCLibraryController : NSObject
@property (readwrite, weak) MCCursorLibrary *appliedTheme;
@property (nonatomic, readonly) NSUndoManager *undoManager;
@property (readonly, copy) NSURL *libraryURL;

- (instancetype)initWithURL:(NSURL *)url;

- (void)importThemeAtURL:(NSURL *)url;
- (void)importTheme:(MCCursorLibrary *)theme;

- (void)addTheme:(MCCursorLibrary *)theme;
- (void)removeTheme:(MCCursorLibrary *)theme;

- (void)applyTheme:(MCCursorLibrary *)theme;
- (void)restoreTheme;

- (NSURL *)URLForTheme:(MCCursorLibrary *)theme;

- (NSSet *)themesWithIdentifier:(NSString *)identifier;
- (BOOL)dumpCursorsWithProgressBlock:(BOOL (^)(NSUInteger current, NSUInteger total))block;

@end

@interface MCLibraryController (Themes)
@property (nonatomic, readonly) NSSet *themes;
@end
