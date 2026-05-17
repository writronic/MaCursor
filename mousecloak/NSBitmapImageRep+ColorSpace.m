#import "NSBitmapImageRep+ColorSpace.h"

@implementation NSBitmapImageRep (ColorSpace)

- (NSBitmapImageRep *)ensuredSRGBSpace {
    NSColorSpace *targetSpace = [NSColorSpace sRGBColorSpace];
    if (self.colorSpace != NULL) {
        if (self.colorSpace.numberOfColorComponents == 1) {
            targetSpace = [NSColorSpace genericGamma22GrayColorSpace];
        }
    }
    return [self bitmapImageRepByConvertingToColorSpace:targetSpace
                                        renderingIntent:NSColorRenderingIntentDefault];
}

- (NSBitmapImageRep *)retaggedSRGBSpace {
    NSColorSpace *targetSpace = [NSColorSpace sRGBColorSpace];
    if (self.colorSpace != NULL) {
        if (self.colorSpace.numberOfColorComponents == 1) {
            targetSpace = [NSColorSpace genericGamma22GrayColorSpace];
        }
    }
    return [self bitmapImageRepByRetaggingWithColorSpace:targetSpace];
}

@end
