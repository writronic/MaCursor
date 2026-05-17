#include "MCDefs.h"
#import "CGSCursor.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

NSString *defaultCursors[] = {
    @"com.apple.coregraphics.Arrow",
    @"com.apple.coregraphics.IBeam",
    @"com.apple.coregraphics.IBeamXOR",
    @"com.apple.coregraphics.Alias",
    @"com.apple.coregraphics.Copy",
    @"com.apple.coregraphics.Move",
    @"com.apple.coregraphics.ArrowCtx",
    @"com.apple.coregraphics.Wait",
    @"com.apple.coregraphics.Empty",
    @"com.apple.coregraphics.ArrowS",
    @"com.apple.coregraphics.IBeamS",
    nil };

NSString *MCErrorDomain = @"com.writronic.macursor.error";

const CGFloat   MCCursorCreatorVersion               = 2.0;
const CGFloat   MCCursorParserVersion                = 2.0;

NSString * const MCCursorDictionaryMinimumVersionKey  = @"MinimumVersion";
NSString * const MCCursorDictionaryVersionKey         = @"Version";
NSString * const MCCursorDictionaryCursorsKey         = @"Cursors";
NSString * const MCCursorDictionaryAuthorKey          = @"Author";
NSString * const MCCursorDictionaryCloudKey           = @"Cloud";
NSString * const MCCursorDictionaryHiDPIKey           = @"HiDPI";
NSString * const MCCursorDictionaryIdentifierKey      = @"Identifier";
NSString * const MCCursorDictionaryThemeNameKey        = @"ThemeName";
NSString * const MCCursorDictionaryThemeVersionKey     = @"ThemeVersion";

NSString * const MCCursorDictionaryFrameCountKey      = @"FrameCount";
NSString * const MCCursorDictionaryFrameDurationKey   = @"FrameDuration";
NSString * const MCCursorDictionaryHotSpotXKey        = @"HotSpotX";
NSString * const MCCursorDictionaryHotSpotYKey        = @"HotSpotY";
NSString * const MCCursorDictionaryPointsWideKey      = @"PointsWide";
NSString * const MCCursorDictionaryPointsHighKey      = @"PointsHigh";
NSString * const MCCursorDictionaryRepresentationsKey = @"Representations";

NSString *UUID() {
    CFUUIDRef theUUID = CFUUIDCreate(NULL);
    CFStringRef string = CFUUIDCreateString(NULL, theUUID);
    CFRelease(theUUID);
    return CFBridgingRelease(string);
}

NSString *MMGet(NSString *prompt) {
    MMOut("%s: ", prompt.UTF8String);
    NSFileHandle *input = [NSFileHandle fileHandleWithStandardInput];
    NSData *data = [input availableData];
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [str stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

NSData *pngDataForImage(id image) {
    if ([image isKindOfClass:[NSBitmapImageRep class]]) {
        return [(NSBitmapImageRep *)image representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    }
    
    CFTypeID typeID = CFGetTypeID((__bridge CFTypeRef)image);
    if (typeID == CGImageGetTypeID()) {
        CGImageRef obj = (__bridge CGImageRef)image;
        CFMutableDataRef mutableData = CFDataCreateMutable(kCFAllocatorDefault, 0);
        CGImageDestinationRef dest = CGImageDestinationCreateWithData(mutableData, (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);
        CGImageDestinationAddImage(dest, obj, NULL);
        CGImageDestinationFinalize(dest);
        
        CFRelease(dest);
        
        return CFBridgingRelease(mutableData);
    }
    
    MMLog("pngDataForImage: unsupported type");
    return nil;
}

NSDictionary *cursorThemeWithIdentifier(NSString *identifier) {
    
    NSUInteger frameCount;
    CGFloat frameDuration;
    CGPoint hotSpot;
    CGSize size;
    CFArrayRef representations;
    bool registered = false;
    
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)identifier.UTF8String, &registered);
    if (!registered)
        return nil;

    CGError error = 0;
    if (![identifier hasPrefix:@"com.apple.cursor"]) {
        error = CGSCopyRegisteredCursorImages(CGSMainConnectionID(), (char*)identifier.UTF8String, &size, &hotSpot, &frameCount, &frameDuration, &representations);
    } else {
        error = CoreCursorCopyImages(CGSMainConnectionID(), [[identifier pathExtension] intValue], &representations, &size, &hotSpot, &frameCount, &frameDuration);
    }
    
    if (error || !representations || !CFArrayGetCount(representations))
        return nil;
    
    NSDictionary *dict = @{MCCursorDictionaryFrameCountKey: @(frameCount), MCCursorDictionaryFrameDurationKey: @(frameDuration), MCCursorDictionaryHotSpotXKey: @(hotSpot.x), MCCursorDictionaryHotSpotYKey: @(hotSpot.y), MCCursorDictionaryPointsWideKey: @(size.width), MCCursorDictionaryPointsHighKey: @(size.height), MCCursorDictionaryRepresentationsKey: CFBridgingRelease(representations)};
    
    return dict;
}

NSDictionary *cursorMap(void) {
    static NSDictionary *cursorNameMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cursorNameMap = [NSDictionary dictionaryWithObjectsAndKeys:
                          @"Resize N-S", @"com.apple.cursor.23",
                          @"Camera 2", @"com.apple.cursor.9",
                          @"IBeam H.", @"com.apple.cursor.26",
                          @"Window NE", @"com.apple.cursor.29",
                          @"Busy", @"com.apple.cursor.4",
                          @"Ctx Arrow", @"com.apple.coregraphics.ArrowCtx",
                          @"Open", @"com.apple.cursor.12",
                          @"Window N-S", @"com.apple.cursor.32",
                          @"Window SE", @"com.apple.cursor.35",
                          @"Counting Down", @"com.apple.cursor.15",
                          @"Window W", @"com.apple.cursor.38",
                          @"Resize E", @"com.apple.cursor.18",
                          @"Cell", @"com.apple.cursor.41",
                          @"Resize N", @"com.apple.cursor.21",
                          @"Copy Drag", @"com.apple.cursor.5",
                          @"Ctx Menu", @"com.apple.cursor.24",
                          @"Window E", @"com.apple.cursor.27",
                          @"Window NE-SW", @"com.apple.cursor.30",
                          @"Camera", @"com.apple.cursor.10",
                          @"Window NW", @"com.apple.cursor.33",
                          @"Pointing", @"com.apple.cursor.13",
                          @"IBeamXOR", @"com.apple.coregraphics.IBeamXOR",
                          @"Copy", @"com.apple.coregraphics.Copy",
                          @"Arrow", @"com.apple.coregraphics.Arrow",
                          @"Counting Up/Down", @"com.apple.cursor.16",
                          @"Window S", @"com.apple.cursor.36",
                          @"Resize Square", @"com.apple.cursor.39",
                          @"Resize W-E", @"com.apple.cursor.19",
                          @"Zoom In", @"com.apple.cursor.42",
                          @"Resize S", @"com.apple.cursor.22",
                          @"IBeam", @"com.apple.coregraphics.IBeam",
                          @"Move", @"com.apple.coregraphics.Move",
                          @"Crosshair", @"com.apple.cursor.7",
                          @"Poof", @"com.apple.cursor.25",
                          @"Wait", @"com.apple.coregraphics.Wait",
                          @"Link", @"com.apple.cursor.2",
                          @"Window E-W", @"com.apple.cursor.28",
                          @"Window N", @"com.apple.cursor.31",
                          @"Closed", @"com.apple.cursor.11",
                          @"Alias", @"com.apple.coregraphics.Alias",
                          @"Empty", @"com.apple.coregraphics.Empty",
                          @"Counting Up", @"com.apple.cursor.14",
                          @"Window NW-SE", @"com.apple.cursor.34",
                          @"Crosshair 2", @"com.apple.cursor.8",
                          @"Window SW", @"com.apple.cursor.37",
                          @"Resize W", @"com.apple.cursor.17",
                          @"Help", @"com.apple.cursor.40",
                          @"Forbidden", @"com.apple.cursor.3",
                          @"Cell XOR", @"com.apple.cursor.20",
                          @"Zoom Out", @"com.apple.cursor.43",
                          @"Arrow (Tahoe)", @"com.apple.coregraphics.ArrowS",
                          @"IBeam (Tahoe)", @"com.apple.coregraphics.IBeamS",
                          nil];
    });
    
    return cursorNameMap;
}

NSString *nameForCursorIdentifier(NSString *identifier) {
    NSString *name = cursorMap()[identifier];
    return name ?: @"Unknown";
}

NSString *cursorIdentifierForName(NSString *name) {
    NSArray *keys = [cursorMap() allKeysForObject:name];
    if (keys.count)
        return keys[0];
    return UUID();
}

CGError MCIsCursorRegistered(CGSConnectionID cid, char *cursorName, bool *registered) {
    
    size_t size = 0;
    CGError err = 0;
    err = CGSGetRegisteredCursorDataSize(cid, cursorName, &size);
    
    *registered = !((BOOL)err) && size > 0;
    
    return err;
}

static NSString *safeFirstKeyForObject(NSDictionary *dict, NSString *object) {
    NSArray *keys = [dict allKeysForObject:object];
    return keys.count > 0 ? keys[0] : nil;
}

BOOL MCCursorIsPointer(NSString *identifier) {
    static NSArray *pointers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *c = cursorMap();
        NSArray *candidates = @[
            safeFirstKeyForObject(c, @"Alias") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Arrow") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Busy") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Closed") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Copy Drag") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Counting Down") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Counting Up") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Counting Up/Down") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Ctx Menu") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Forbidden") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Link") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Move") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Open") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Pointing") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Poof") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Wait") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Zoom In") ?: [NSNull null],
            safeFirstKeyForObject(c, @"Zoom Out") ?: [NSNull null],
        ];
        NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:candidates.count];
        for (id obj in candidates) {
            if (obj != [NSNull null]) {
                [filtered addObject:obj];
            }
        }
        pointers = [filtered copy];
    });

    return [pointers containsObject:identifier];
}

BOOL MCIsTahoeOrLater(void) {
    static BOOL checked = NO;
    static BOOL isTahoe = NO;
    if (!checked) {
        NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
        isTahoe = (version.majorVersion >= 26);
        checked = YES;
    }
    return isTahoe;
}

NSArray *MCTahoeCursorAliasesForIdentifier(NSString *identifier) {
    if (!MCIsTahoeOrLater()) return nil;

    static NSDictionary *aliasMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        aliasMap = @{
            @"com.apple.coregraphics.Arrow": @[ @"com.apple.coregraphics.ArrowS" ],
            @"com.apple.coregraphics.IBeam": @[ @"com.apple.coregraphics.IBeamS" ],
            @"com.apple.coregraphics.ArrowS": @[ @"com.apple.coregraphics.Arrow" ],
            @"com.apple.coregraphics.IBeamS": @[ @"com.apple.coregraphics.IBeam" ],
        };
    });

    return aliasMap[identifier];
}
