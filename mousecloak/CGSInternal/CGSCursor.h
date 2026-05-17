#pragma once
#include "CGSConnection.h"
#import <ApplicationServices/ApplicationServices.h>

typedef int CGSCursorID;

CG_EXTERN CGError CoreCursorUnregisterAll(CGSConnectionID cid);
CG_EXTERN CGError CoreCursorSet(CGSConnectionID cid, CGSCursorID cursorID);
CG_EXTERN CGError CoreCursorSetAndReturnSeed(CGSConnectionID cid, CGSCursorID cursorNum, int *seed);
CG_EXTERN CGError CoreCursorCopyImages(CGSConnectionID cid, CGSCursorID cursorID, CFArrayRef *images, CGSize *imageSize, CGPoint *hotSpot, NSUInteger *frameCount, CGFloat *frameDuration);

#if defined(MAC_OS_X_VERSION_10_8)
CG_EXTERN CGError CGSCopyRegisteredCursorImages(CGSConnectionID cid, char *cursorName, CGSize *imageSize, CGPoint *hotSpot, NSUInteger *frameCount, CGFloat *frameDuration, CFArrayRef *imageArray);
#endif

CG_EXTERN CGError CGSGetRegisteredCursorImages(CGSConnectionID cid, char *cursorName, CGSize *imageSize, CGPoint *hotSpot, NSUInteger *frameCount, CGFloat *frameDuration, CFArrayRef *imageArray);

CG_EXTERN CGError CGSRegisterCursorWithImages(CGSConnectionID cid, char *cursorName, bool setGlobally, bool instantly, CGSize cursorSize, CGPoint hotspot, NSUInteger frameCount, CGFloat frameDuration, CFArrayRef imageArray, int *seed);

CG_EXTERN CGError CGSSetSystemDefinedCursor(CGSConnectionID cid, CGSCursorID cursor);

CG_EXTERN void CGSSetSystemDefinedCursorWithSeed(CGSConnectionID connection, CGSCursorID systemCursor, int *cursorSeed);

CG_EXTERN void CGSSetDockCursorOverride(CGSConnectionID cid, bool flag);

CG_EXTERN CGError CGSGetRegisteredCursorDataSize(CGSConnectionID cid, char *cursorName, size_t *size);

CG_EXTERN CGImageRef CGSCreateRegisteredCursorImage(CGSConnectionID cid, char *cursorName, CGPoint *hotSpot);

CG_EXTERN CGError CGSSetRegisteredCursor(CGSConnectionID cid, char *cursorName, int *seed);

CG_EXTERN CGError CGSGetRegisteredCursorData2(CGSConnectionID cid, char *cursorName, void *data, size_t *dataSize, int *bytesPerRow, CGSize *imageSize, CGSize *cursorSize, CGPoint *hotSpot, int *bitsPerPixel, int *samplesPerPixel, int *bitsPerSample, int *frameCount, float *frameDuration);

CG_EXTERN CGError CGSRemoveRegisteredCursor(CGSConnectionID cid, char *cursorName, bool unknownFlag);
CG_EXTERN CGError CGSGetRegisteredCursorData(CGSConnectionID cid, char *cursorName, void *data, int *dataSize, CGSize *cursorSize, CGPoint *hotSpot, int *depth, int *bitsPerPixel, int *samplesPerPixel, int *bitsPerSample, int *unknown);
CG_EXTERN CGError CGSRegisterCursorWithImage(CGSConnectionID, char *, bool, bool, int, CGImageRef, CGSize, CGPoint, int *, CGFloat, CGFloat);
CG_EXTERN CGError CGSRegisterCursorWithData(CGSConnectionID cid, char *cursorName, char, bool, bool, CGSize, CGRect, CGPoint, int, int, int, int, int, int, int, int, int, int, int);

extern NSArray *MCTahoeCursorAliasesForIdentifier(NSString *identifier);

#define MC_MAX_CORE_CURSOR_ID 43

CG_EXTERN CGError CGSSystemSupportsHardwareCursor(CGSConnectionID cid, bool *outSupportsHardwareCursor);

CG_EXTERN CGError CGSSystemSupportsColorHardwareCursor(CGSConnectionID cid, bool *outSupportsHardwareCursor);

CG_EXTERN CGError CGSShowCursor(CGSConnectionID cid);

CG_EXTERN CGError CGSHideCursor(CGSConnectionID cid);

CG_EXTERN CGError CGSObscureCursor(CGSConnectionID cid);

CG_EXTERN CGError CGSGetCurrentCursorLocation(CGSConnectionID cid, CGPoint *outPos);

CG_EXTERN char *CGSCursorNameForSystemCursor(CGSCursorID cursor);

CG_EXTERN CGError CGSGetCursorDataSize(CGSConnectionID cid, int *outDataSize);

CG_EXTERN CGError CGSGetCursorData(CGSConnectionID cid, void *outData);

CG_EXTERN CGError CGSGetGlobalCursorDataSize(CGSConnectionID cid, int *outDataSize);

CG_EXTERN CGError CGSGetGlobalCursorData(CGSConnectionID cid, void *outData, int *outDataSize, CGSize *outSize, CGPoint *outHotSpot, int *outDepth, int *outComponents, int *outBitsPerComponent, int *m);

CG_EXTERN CGError CGSGetSystemDefinedCursorDataSize(CGSConnectionID cid, CGSCursorID cursor, int *outDataSize);

CG_EXTERN CGError CGSGetSystemDefinedCursorData(CGSConnectionID cid, CGSCursorID cursor, void *outData, int *outRowBytes, CGRect *outRect, CGRect *outHotSpot, int *outDepth, int *outComponents, int *outBitsPerComponent, int *mystery);

CG_EXTERN int CGSCurrentCursorSeed(void);

CG_EXTERN CGError CGSForceWaitCursorActive(CGSConnectionID cid, bool showWaitCursor);
