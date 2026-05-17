#pragma once

#import <Foundation/Foundation.h>

#define kMCDomain @"com.writronic.MaCursor"

extern NSString *MCPreferencesAppliedCursorKey;
extern NSString *MCPreferencesAppliedClickActionKey;
extern NSString *MCPreferencesCursorScaleKey;
extern NSString *MCPreferencesDoubleActionKey;
extern NSString *MCPreferencesHandednessKey;
extern NSString *MCSuppressDeleteLibraryConfirmationKey;
extern NSString *MCSuppressDeleteCursorConfirmationKey;
extern id MCDefaultFor(NSString *key, NSString *user, NSString *host);
extern id MCDefault(NSString *key);
#define MCFlag(key) [MCDefault(key) boolValue]

extern void MCSetDefaultFor(id value, NSString *key, NSString *user, NSString *host);
#define MCSetDefault(value, key) MCSetDefaultFor(value, key, (__bridge NSString *)kCFPreferencesCurrentUser, (__bridge NSString *)kCFPreferencesCurrentHost)
#define MCSetFlag(value, key) MCSetDefault(@(value), key)
