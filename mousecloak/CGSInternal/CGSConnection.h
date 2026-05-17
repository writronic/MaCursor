#pragma once

#include <ApplicationServices/ApplicationServices.h>

typedef int CGSConnectionID;
static const CGSConnectionID kCGSNullConnectionID = 0;

CG_EXTERN CGError CGSSetLoginwindowConnection(CGSConnectionID cid) AVAILABLE_MAC_OS_X_VERSION_10_5_AND_LATER;
CG_EXTERN CGError CGSSetLoginwindowConnectionWithOptions(CGSConnectionID cid, CFDictionaryRef options) AVAILABLE_MAC_OS_X_VERSION_10_5_AND_LATER;

CG_EXTERN CGError CGSDisableUpdate(CGSConnectionID cid);
CG_EXTERN CGError CGSReenableUpdate(CGSConnectionID cid);

CG_EXTERN bool CGSMenuBarExists(CGSConnectionID cid);

typedef void (*CGSNewConnectionNotificationProc)(CGSConnectionID cid);
CG_EXTERN CGError CGSRegisterForNewConnectionNotification(CGSNewConnectionNotificationProc proc);
CG_EXTERN CGError CGSRemoveNewConnectionNotification(CGSNewConnectionNotificationProc proc);

typedef void (*CGSConnectionDeathNotificationProc)(CGSConnectionID cid);
CG_EXTERN CGError CGSRegisterForConnectionDeathNotification(CGSConnectionDeathNotificationProc proc);
CG_EXTERN CGError CGSRemoveConnectionDeathNotification(CGSConnectionDeathNotificationProc proc);

CG_EXTERN CGError CGSNewConnection(int unused, CGSConnectionID *outConnection);

CG_EXTERN CGError CGSReleaseConnection(CGSConnectionID cid);

CG_EXTERN CGSConnectionID _CGSDefaultConnection(void);
CG_EXTERN CGSConnectionID CGSMainConnectionID(void);

CG_EXTERN CGSConnectionID CGSDefaultConnectionForThread(void);

CG_EXTERN CGError CGSConnectionGetPID(CGSConnectionID cid, pid_t *outPID);

CG_EXTERN CGError CGSGetConnectionIDForPSN(CGSConnectionID cid, const ProcessSerialNumber *psn, CGSConnectionID *outOwnerCID);

CG_EXTERN CGError CGSGetConnectionProperty(CGSConnectionID cid, CGSConnectionID targetCID, CFStringRef key, CFTypeRef *outValue);
CG_EXTERN CGError CGSSetConnectionProperty(CGSConnectionID cid, CGSConnectionID targetCID, CFStringRef key, CFTypeRef value);

CG_EXTERN CGError CGSShutdownServerConnections(void);

CG_EXTERN CGError CGSSetUniversalOwner(CGSConnectionID cid);

CG_EXTERN CGError CGSSetOtherUniversalConnection(CGSConnectionID cid, CGSConnectionID otherConnection);
