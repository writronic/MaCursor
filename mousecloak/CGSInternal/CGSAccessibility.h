#pragma once
#include "CGSConnection.h"

CG_EXTERN bool CGSDisplayIsZoomed(void);
CG_EXTERN CGError CGSIsZoomed(CGSConnectionID cid, bool *outIsZoomed);

CG_EXTERN CGError CGSGetCursorScale(CGSConnectionID cid, float *outScale);
CG_EXTERN CGError CGSSetCursorScale(CGSConnectionID cid, float scale);

CG_EXTERN bool CGDisplayUsesInvertedPolarity(void);
CG_EXTERN void CGDisplaySetInvertedPolarity(bool invertedPolarity);

CG_EXTERN bool CGDisplayUsesForceToGray(void);
CG_EXTERN void CGDisplayForceToGray(bool forceToGray);

CG_EXTERN CGError CGSSetDisplayContrast(float contrast);
