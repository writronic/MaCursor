#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *backupStringForIdentifier(NSString *identifier);
extern BOOL backupCursorForIdentifier(NSString *ident, NSError * _Nullable * _Nullable error);
extern BOOL backupAllCursors(NSError * _Nullable * _Nullable error);

extern BOOL resetAllCursors(NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
