#import "CC27.h"
#import <objc/runtime.h>
#import <string.h>
#import <dlfcn.h>

static void CC27ReloadPrefs(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [CC27Prefs.shared reload];
    [CC27LayoutStore.shared reload];
}

static BOOL CC27ViewIsInControlCenter(UIView *view) {
    UIView *v = view;
    while (v) {
        const char *cls = class_getName(v.class);
        if (cls) {
            if (strstr(cls, "ControlCenter")) return YES;
            if (strstr(cls, "QuickAction") || strstr(cls, "CoverSheet") || strstr(cls, "DashBoard") || strstr(cls, "Dashboard") || strstr(cls, "LockScreen")) return NO;
        }
        v = v.superview;
    }
    return NO;
}

%group CC27

%hook CCUIModularControlCenterOverlayViewController
- (void)viewWillAppear:(BOOL)animated { %orig; if (!CC27Prefs.shared.enabled || [CC27EditSession deviceUILocked]) return; [CC27EditSession.shared setHostVisible:YES host:self]; }
- (void)viewDidAppear:(BOOL)animated { %orig; if (!CC27Prefs.shared.enabled || [CC27EditSession deviceUILocked]) return; [CC27EditSession.shared setHostVisible:YES host:self]; }
- (void)viewWillDisappear:(BOOL)animated { %orig; if (!CC27Prefs.shared.enabled) return; [CC27EditSession.shared setHostVisible:NO host:self]; }
- (void)viewDidDisappear:(BOOL)animated { %orig; if (!CC27Prefs.shared.enabled) return; [CC27EditSession.shared setHostVisible:NO host:self]; }
- (void)viewDidLayoutSubviews { %orig; if (!CC27Prefs.shared.enabled) return; if (CC27EditSession.shared.hostVisible) [CC27EditSession.shared layoutChromeOnHost:self]; }
- (void)setPresentationState:(NSInteger)state { %orig; if (!CC27Prefs.shared.enabled) return; if ([CC27EditSession deviceUILocked]) { [CC27EditSession.shared setHostVisible:NO host:self]; return; } [CC27EditSession.shared updateChromeForPresentationState:state host:self]; }
%end

%hook CCUIContentModuleContentContainerView
- (void)layoutSubviews {
    %orig;
    if (!CC27Prefs.shared.enabled) return;
    if (!CC27ViewIsInControlCenter(self)) return;
    @try {
        if (CC27Prefs.shared.glassChrome && ![CC27EditSession deviceUILocked]) [CC27Glass applyToModuleContainer:self];
        if (CC27EditSession.shared.editing) {
            NSString *identifier = nil; UIView *v = self;
            while (v) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                SEL sel = NSSelectorFromString(@"_viewControllerForAncestor");
                UIViewController *vc = [v respondsToSelector:sel] ? [v performSelector:sel] : nil;
#pragma clang diagnostic pop
                if ([vc isKindOfClass:NSClassFromString(@"CCUIContentModuleContainerViewController")]) { @try { identifier = [vc valueForKey:@"moduleIdentifier"]; } @catch (__unused NSException *e) {} break; }
                v = v.superview;
            }
            if (identifier.length) [CC27EditSession.shared decorateModuleContainer:self identifier:identifier];
        }
    } @catch (NSException *e) { NSLog(@"[CC27] module styling threw (suppressed): %@", e); }
}
%end
%end

static void CC27InstallHooks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!CC27Prefs.shared.enabled) { NSLog(@"[CC27] disabled in prefs — hooks not installed"); return; }
        %init(CC27);
        NSLog(@"[CC27] 1.0.9 hooks installed (post-launch)");
    });
}

%ctor {
    @autoreleasepool {
        NSMutableArray<NSString *> *killPaths = [NSMutableArray array];
        NSString *rel = @"/var/mobile/Library/Preferences/com.kolby.cc27.killswitch";
        const char *(*jbrootFn)(const char *) = (const char *(*)(const char *))dlsym(RTLD_DEFAULT, "jbroot");
        if (jbrootFn) { const char *p = jbrootFn(rel.UTF8String); if (p && p[0]) [killPaths addObject:[NSString stringWithUTF8String:p]]; }
        [killPaths addObject:[@"/var/jb" stringByAppendingString:rel]];
        [killPaths addObject:rel];
        for (NSString *path in killPaths) if ([[NSFileManager defaultManager] fileExistsAtPath:path]) { NSLog(@"[CC27] kill switch present at %@ — not loading", path); return; }
        [CC27Prefs.shared reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CC27ReloadPrefs, CFSTR("com.kolby.cc27/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorCoalesce);
        __block id token = nil;
        token = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            if (token) { [[NSNotificationCenter defaultCenter] removeObserver:token]; token = nil; }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ CC27InstallHooks(); });
        }];
        NSLog(@"[CC27] 1.0.9 loaded — waiting for SpringBoard launch to finish before hooking");
    }
}
