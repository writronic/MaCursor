#import "MCPrefs.h"

NSString *MCPreferencesAppliedCursorKey          = @"MCAppliedCursor";
NSString *MCPreferencesAppliedClickActionKey     = @"MCLibraryClickAction";
NSString *MCPreferencesCursorScaleKey            = @"MCCursorScale";
NSString *MCPreferencesDoubleActionKey           = @"MCDoubleAction";
NSString *MCPreferencesHandednessKey             = @"MCHandedness";
NSString *MCSuppressDeleteLibraryConfirmationKey = @"MCSuppressDeleteLibraryConfirmationKey";
NSString *MCSuppressDeleteCursorConfirmationKey  = @"MCSuppressDeleteCursorConfirmationKey";
id MCDefaultFor(NSString *key, NSString *user, NSString *host) {
    NSString *value = (__bridge_transfer NSString *)CFPreferencesCopyValue((CFStringRef)key, (CFStringRef)kMCDomain, (CFStringRef)user, (CFStringRef)host);
    return value;
}

id MCDefault(NSString *key) {
    return (__bridge_transfer id)CFPreferencesCopyAppValue((CFStringRef)key, (CFStringRef)kMCDomain);
}

void MCSetDefaultFor(id value, NSString *key, NSString *user, NSString *host) {
    CFPreferencesSetValue((CFStringRef)key, (CFPropertyListRef)value, (CFStringRef)kMCDomain, (CFStringRef)user, (CFStringRef)host);
    CFPreferencesSynchronize((CFStringRef)kMCDomain, (CFStringRef)user, (CFStringRef)host);
}
