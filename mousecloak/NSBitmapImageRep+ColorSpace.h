#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSBitmapImageRep (ColorSpace)

- (NSBitmapImageRep *)retaggedSRGBSpace;
- (NSBitmapImageRep *)ensuredSRGBSpace;

@end

NS_ASSUME_NONNULL_END
