#import <Foundation/Foundation.h>
#import <notify.h>
#import "KReader.h"

static void FKTRun(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        /* runDumpPreferringRoot mints IOSurfaces then spawns root helper. */
        NSString *s = [KReader runDumpPreferringRoot];
        NSLog(@"[Lum1naFKT] phase1 %lu bytes → %@",
              (unsigned long)s.length, [KReader dumpPath]);
    });
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    NSLog(@"[Lum1naFKT] SpringBoard up — auto-dump 2s (0.7 leftover catalog); app or notifyutil -p com.lumina.fkt.dump");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ FKTRun(); });
}
%end

%ctor {
    int token = 0;
    notify_register_dispatch("com.lumina.fkt.dump", &token, dispatch_get_main_queue(),
                             ^(int t) { (void)t; FKTRun(); });
}
