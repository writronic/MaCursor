#import "MCLibraryController.h"
#import "apply.h"
#import "restore.h"
#import "create.h"

@interface MCLibraryController ()
@property (nonatomic, readwrite, strong) NSUndoManager *undoManager;
@property (nonatomic, retain) NSMutableSet *themes;
@property (readwrite, copy) NSURL *libraryURL;
- (void)loadLibrary;
- (void)willSaveNotification:(NSNotification *)note;
@end

@implementation MCLibraryController

- (NSURL *)URLForTheme:(MCCursorLibrary *)theme {
    return [NSURL fileURLWithPathComponents:@[ self.libraryURL.path, [theme.identifier stringByAppendingPathExtension:@"cursor"] ]];;
}

- (instancetype)initWithURL:(NSURL *)url {
    if ((self = [self init])) {
        self.libraryURL = url;
        self.undoManager = [[NSUndoManager alloc] init];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willSaveNotification:) name:MCLibraryWillSaveNotificationName object:nil];
        [self loadLibrary];
    }
    
    return self;
}

- (void)loadLibrary {
    [self.undoManager disableUndoRegistration];
    
    self.themes = [NSMutableSet set];
    NSString *themesPath = self.libraryURL.path;
    NSArray  *contents  = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:themesPath error:NULL];
    NSString *applied   = MCDefault(MCPreferencesAppliedCursorKey);

    for (NSString *filename in contents) {
        if ([filename hasPrefix:@"."])
            continue;

        NSURL *fileURL = [NSURL fileURLWithPathComponents:@[ themesPath, filename ]];
        MCCursorLibrary *library = [MCCursorLibrary cursorLibraryWithContentsOfURL:fileURL];
        
        if ([library.identifier isEqualToString:applied]) {
            self.appliedTheme = library;
        }
        
        [self addTheme:library];
    }
    
    [self.undoManager enableUndoRegistration];
}

- (void)importThemeAtURL:(NSURL *)url {
    [self importTheme:[MCCursorLibrary cursorLibraryWithContentsOfURL:url]];
}

- (void)importTheme:(MCCursorLibrary *)lib {
    if ([[self.themes valueForKeyPath:@"identifier"] containsObject:lib.identifier]) {
        lib.identifier = [lib.identifier stringByAppendingFormat:@".%@", UUID()];
    }

    lib.fileURL = [self URLForTheme:lib];
    [lib writeToFile:lib.fileURL.path atomically:NO];
    
    [self addTheme:lib];
}

- (void)addTheme:(MCCursorLibrary *)theme {
    if (!theme) {
        NSLog(@"Cannot add nil cursor theme");
        return;
    }

    if ([self.themes containsObject:theme] || [[self.themes valueForKeyPath:@"identifier"] containsObject:theme.identifier]) {
        NSLog(@"Not adding %@ to the library because an object with that identifier already exists", theme.identifier);
        return;
    }

    NSSet *change = [NSSet setWithObject:theme];
    [self willChangeValueForKey:@"themes" withSetMutation:NSKeyValueUnionSetMutation usingObjects:change];

    theme.library = self;
    [self.themes addObject:theme];

    [[self.undoManager prepareWithInvocationTarget:self] removeTheme:theme];
    if (!self.undoManager.isUndoing) {
        [self.undoManager setActionName:[@"Add " stringByAppendingString:theme.name ?: @"Theme"]];
    }
    
    [self didChangeValueForKey:@"themes" withSetMutation:NSKeyValueUnionSetMutation usingObjects:change];

    [theme.undoManager removeAllActions];
}

- (void)removeTheme:(MCCursorLibrary *)theme {
    NSSet *change = [NSSet setWithObject:theme];
    
    [self willChangeValueForKey:@"themes" withSetMutation:NSKeyValueMinusSetMutation usingObjects:change];
    if (theme == self.appliedTheme)
        [self restoreTheme];

    if (theme.library == self)
        theme.library = nil;
    
    [self.themes removeObject:theme];
    
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *destinationURL = [NSURL fileURLWithPath:[[@"~/.Trash" stringByExpandingTildeInPath] stringByAppendingPathComponent:theme.fileURL.lastPathComponent] isDirectory:NO];
    
    [manager removeItemAtURL:destinationURL error:NULL];
    [manager moveItemAtURL:theme.fileURL toURL:destinationURL error:NULL];

    [[self.undoManager prepareWithInvocationTarget:self] importThemeAtURL:destinationURL];
    if (!self.undoManager.isUndoing) {
        [self.undoManager setActionName:[@"Remove " stringByAppendingString:theme.name ?: @"Theme"]];
    }
    
    [self didChangeValueForKey:@"themes" withSetMutation:NSKeyValueMinusSetMutation usingObjects:change];
}

- (void)applyTheme:(MCCursorLibrary *)theme {
    if (applyThemeAtPath(theme.fileURL.path)) {
        self.appliedTheme = theme;
    }
}

- (void)restoreTheme {
    resetAllCursors(NULL);
    self.appliedTheme = nil;
}

- (NSSet *)themesWithIdentifier:(NSString *)identifier {
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"identifier == %@", identifier];
    return [self.themes filteredSetUsingPredicate:pred];
}

- (void)willSaveNotification:(NSNotification *)note {
    MCCursorLibrary *theme = note.object;
    NSURL *oldURL = theme.fileURL;
    [theme setFileURL:[self URLForTheme:theme]];
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtURL:oldURL error:&error];

    if (error) {
        NSLog(@"error removing cursor theme after rename: %@", error);
    }

}

- (BOOL)dumpCursorsWithProgressBlock:(BOOL (^)(NSUInteger current, NSUInteger total))block {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat: @"%@ (%f).cursor",
                       NSLocalizedString(@"MaCursor Dump", @"MaCursor dump cursor file name"),
                       NSDate.date.timeIntervalSince1970]];
    if (dumpCursorsToFile(path, block)) {
        __weak MCLibraryController *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf importThemeAtURL:[NSURL fileURLWithPath:path]];
        });
        return YES;
    }

    return NO;
}

@end
