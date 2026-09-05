#pragma once

#import <Cocoa/Cocoa.h>

#define MMOut(format, ...) fprintf(stdout, format, ## __VA_ARGS__)
#define MMLog(format, ...) MMOut(format "\n", ## __VA_ARGS__)

#import "CGSPrivateCursor.h"
#import "CGSPrivateAccessibility.h"

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

static const NSUInteger MACMaxFrameCount               = 24;
static const NSUInteger MACMaxImportFrameCount          = 128;
static const float      MACDumpCursorScale             = 16.0f;
static const float      MACCursorRefreshScaleBumpSmall = 0.1f;
static const float      MACCursorRefreshScaleBumpLarge = 0.3f;
static const float      MACMaxCursorScale              = 32.0f;
static const float      MACMinCursorScale              = 0.5f;
static const float      MACMaxDefaultCursorScale       = 16.0f;
static const CGFloat    MACMaxCursorPointSize          = 128.0;
static const CGFloat    MACBaseCursorPointSize         = 32.0;
static const NSTimeInterval MACWindowDismissDelay       = 0.05;

extern NSString * _Nonnull defaultCursors[];

NS_ASSUME_NONNULL_BEGIN

extern NSString * const MACCursorDictionaryCursorsKey;
extern NSString * const MACCursorDictionaryCreatorKey;
extern NSString * const MACCursorDictionaryHiDPIKey;
extern NSString * const MACCursorDictionaryIdentifierKey;
extern NSString * const MACCursorDictionaryThemeNameKey;
extern NSString * const MACCursorDictionaryThemeVersionKey;
extern NSString * const MACCursorDictionaryUUIDKey;
extern NSString * const MACCursorDictionaryFrameCountKey;
extern NSString * const MACCursorDictionaryFrameDurationKey;
extern NSString * const MACCursorDictionaryHotSpotXKey;
extern NSString * const MACCursorDictionaryHotSpotYKey;
extern NSString * const MACCursorDictionaryPointsWideKey;
extern NSString * const MACCursorDictionaryPointsHighKey;
extern NSString * const MACCursorDictionaryRepresentationsKey;

extern NSDictionary *cursorMap(void);
extern NSString *nameForCursorIdentifier(NSString *identifier);
extern NSString *UUID(void);
extern NSDictionary * _Nullable cursorThemeWithIdentifier(NSString *identifier);
extern NSData *pngDataForImage(id image);
extern CGError MACIsCursorRegistered(CGSConnectionID cid, char *cursorName, bool *registered);
extern NSArray * _Nullable MACTahoeCursorAliasesForIdentifier(NSString *identifier);
extern NSArray * _Nullable MACBrowserCursorAliasesForIdentifier(NSString *identifier);
extern BOOL MACIsTahoeOrLater(void);
extern BOOL MACCaptureSystemDefaults(NSString *outputPath);
extern BOOL MACPerformCursorCapture(NSString *outputPath);
extern NSString * _Nonnull MACSystemDefaultCursorPath(void);

#define kMACDomain @"com.writronic.MaCursor"

extern NSString *MACPreferencesAppliedCursorKey;
extern NSString *MACPreferencesCursorScaleKey;
extern NSString *MACPreferencesHandednessKey;
extern NSString *MACPreferencesCursorShadowKey;
extern NSString *MACSuppressDeleteLibraryConfirmationKey;
extern NSString *MACSuppressDeleteCursorConfirmationKey;
extern id MACDefaultFor(NSString *key, NSString *user, NSString *host);
extern id MACDefault(NSString *key);
extern BOOL MACResolvePreferredCursorScale(NSNumber * _Nullable prefValue, float * _Nullable outScale);
#define MACFlag(key) [MACDefault(key) boolValue]
extern void MACSetDefaultFor(id _Nullable value, NSString *key, NSString *user, NSString *host);
#define MACSetDefault(value, key) MACSetDefaultFor(value, key, (__bridge NSString *)kCFPreferencesCurrentUser, (__bridge NSString *)kCFPreferencesCurrentHost)
#define MACSetFlag(value, key) MACSetDefault(@(value), key)

@interface NSBitmapImageRep (ColorSpace)
- (NSBitmapImageRep *)retaggedSRGBSpace;
- (NSBitmapImageRep *)ensuredSRGBSpace;
@end

NS_ASSUME_NONNULL_END
