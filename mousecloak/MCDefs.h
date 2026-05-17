#pragma once

#import <Cocoa/Cocoa.h>

#define MMOut(format, ...) fprintf(stdout, format, ## __VA_ARGS__)
#define MMLog(format, ...) MMOut(format "\n", ## __VA_ARGS__)

#import "CGSCursor.h"
#import "CGSAccessibility.h"

#define RESET   "\033[0m"
#define BLACK   "\033[30m"
#define RED     "\033[31m"
#define GREEN   "\033[32m"
#define YELLOW  "\033[33m"
#define BLUE    "\033[34m"
#define MAGENTA "\033[35m"
#define CYAN    "\033[36m"
#define WHITE   "\033[37m"
#define BOLD    "\033[1m"

static const NSUInteger MCMaxFrameCount               = 24;
static const NSUInteger MCMaxImportFrameCount          = 128;
static const float      MCDumpCursorScale             = 16.0f;
static const float      MCCursorRefreshScaleBumpSmall = 0.1f;
static const float      MCCursorRefreshScaleBumpLarge = 0.3f;
static const float      MCMaxCursorScale              = 32.0f;
static const float      MCMinCursorScale              = 1.0f;
static const float      MCMaxDefaultCursorScale       = 16.0f;
static const NSTimeInterval MCWindowDismissDelay       = 0.05;

extern NSString * _Nonnull defaultCursors[];

NS_ASSUME_NONNULL_BEGIN

extern NSString *MCErrorDomain;
extern NSDictionary *cursorNameMap;

typedef NS_ENUM(NSInteger, MCErrorCode) {
    MCErrorInvalidThemeCode = -1,
    MCErrorWriteFailCode   = -2,
    
    MCErrorInvalidFormatCode = -100,
    MCErrorMultipleCursorIdentifiersCode = -101
};

extern const CGFloat   MCCursorCreatorVersion;
extern const CGFloat   MCCursorParserVersion;
extern NSString * const MCCursorDictionaryMinimumVersionKey;
extern NSString * const MCCursorDictionaryVersionKey;
extern NSString * const MCCursorDictionaryCursorsKey;
extern NSString * const MCCursorDictionaryAuthorKey;
extern NSString * const MCCursorDictionaryCloudKey;
extern NSString * const MCCursorDictionaryHiDPIKey;
extern NSString * const MCCursorDictionaryIdentifierKey;
extern NSString * const MCCursorDictionaryThemeNameKey;
extern NSString * const MCCursorDictionaryThemeVersionKey;

extern NSString * const MCCursorDictionaryFrameCountKey;
extern NSString * const MCCursorDictionaryFrameDurationKey;
extern NSString * const MCCursorDictionaryHotSpotXKey;
extern NSString * const MCCursorDictionaryHotSpotYKey;
extern NSString * const MCCursorDictionaryPointsWideKey;
extern NSString * const MCCursorDictionaryPointsHighKey;
extern NSString * const MCCursorDictionaryRepresentationsKey;

extern NSDictionary *cursorMap(void);
extern NSString *nameForCursorIdentifier(NSString *identifier);
extern NSString *cursorIdentifierForName(NSString *name);

extern NSString *UUID(void);
extern NSDictionary * _Nullable cursorThemeWithIdentifier(NSString *identifier);
extern NSData *pngDataForImage(id image);
extern NSString *MMGet(NSString *prompt);

extern CGError MCIsCursorRegistered(CGSConnectionID cid, char *cursorName, bool *registered);
extern BOOL MCCursorIsPointer(NSString *identifier);

extern NSArray * _Nullable MCTahoeCursorAliasesForIdentifier(NSString *identifier);
extern BOOL MCIsTahoeOrLater(void);

NS_ASSUME_NONNULL_END
