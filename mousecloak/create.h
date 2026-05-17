#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSError * _Nullable createCursorTheme(NSString *input, NSString *output);

extern NSDictionary * _Nullable processedCursorThemeWithIdentifier(NSString *identifier);
extern BOOL dumpCursorsToFile(NSString *path, BOOL (^progress)(NSUInteger current, NSUInteger total));

extern NSDictionary * _Nullable createCursorThemeFromDirectory(NSString *path);

extern void exportCursorTheme(NSDictionary *theme, NSString *destination);

NS_ASSUME_NONNULL_END
