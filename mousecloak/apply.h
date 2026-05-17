#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern BOOL applyCursorForIdentifier(NSUInteger frameCount, CGFloat frameDuration, CGPoint hotSpot, CGSize size, NSArray *images, NSString *ident, NSUInteger repeatCount);
extern BOOL applyThemeForIdentifier(NSDictionary *cursor, NSString *identifier, BOOL restore);
extern BOOL applyTheme(NSDictionary *dictionary);
extern BOOL applyThemeAtPath(NSString *path);

extern void MCFinalizeCursorApply(float scaleBump);

NS_ASSUME_NONNULL_END
