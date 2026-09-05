#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern BOOL applyCursorForIdentifier(NSUInteger frameCount, CGFloat frameDuration, CGPoint hotSpot, CGSize size, NSArray *images, NSString *ident, NSUInteger repeatCount);
extern NSArray *MACPrepareCursorImages(NSArray *images, CGSize size, NSUInteger *frameCount, CGFloat *frameDuration);
extern BOOL applyThemeForIdentifier(NSDictionary *cursor, NSString *identifier, BOOL restore);
extern BOOL applyTheme(NSDictionary *dictionary);
extern BOOL applyThemeAtPath(NSString *path);
extern void MACFinalizeCursorApply(float scaleBump);

extern NSDictionary * _Nullable processedCursorThemeWithIdentifier(NSString *identifier);
extern BOOL dumpCursorsToFile(NSString *path, BOOL (^progress)(NSUInteger current, NSUInteger total));

extern BOOL resetAllCursors(NSError * _Nullable * _Nullable error);

extern float cursorScale(void);
extern float defaultCursorScale(void);
extern BOOL setCursorScale(float scale);
extern BOOL assertPreferredCursorScale(void);

NS_ASSUME_NONNULL_END
