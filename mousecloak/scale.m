#import "scale.h"
#import "MCPrefs.h"
#import "MCDefs.h"

float cursorScale() {
    float value;
    CGSGetCursorScale(CGSMainConnectionID(), &value);
    return value;
}

float defaultCursorScale() {
    float scale = [MCDefault(MCPreferencesCursorScaleKey) floatValue];
    if (scale < MCMinCursorScale || scale > MCMaxDefaultCursorScale)
        scale = 1;
    return scale;
}

BOOL setCursorScale(float dbl) {
    if (dbl > MCMaxCursorScale) {
        MMLog("Not a good idea...");
        return NO;
    } else if (CGSSetCursorScale(CGSMainConnectionID(), dbl) == noErr) {
        MMLog("Successfully set cursor scale!");
        return YES;
    } else {
        MMLog("Somehow failed to set cursor scale!");
        return NO;
    }
}
