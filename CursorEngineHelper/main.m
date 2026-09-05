#import <Foundation/Foundation.h>
#import "MACCursorDaemon.h"
#import "MACFocusFollowsMouse.h"

int main(int argc, char * argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], MACFFMTrustProbeArgument) == 0) {
            return MACFocusFollowsMouseTrustProbeMain();
        }
        listener();
        return EXIT_SUCCESS;
    }
}
