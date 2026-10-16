#import "Sk1nRespring.h"
#import "SPKRuntime.h"
#import <spawn.h>

extern char **environ;

void Sk1nSetActiveSkin(NSString *skinID) {
    CFPreferencesSetValue(CFSTR("activeSkin"), (__bridge CFStringRef)skinID,
                          CFSTR("com.kolby.sk1n"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(CFSTR("com.kolby.sk1n"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

static BOOL Sk1nSpawn(NSString *path, NSArray<NSString *> *args) {
    if (![NSFileManager.defaultManager isExecutableFileAtPath:path]) return NO;
    NSMutableArray *all = [NSMutableArray arrayWithObject:path];
    [all addObjectsFromArray:args];
    char *argv[16] = {0};
    for (NSUInteger i = 0; i < all.count && i < 15; i++) argv[i] = (char *)[all[i] fileSystemRepresentation];
    pid_t pid = 0;
    return posix_spawn(&pid, argv[0], NULL, NULL, argv, environ) == 0;
}

BOOL Sk1nRespringNow(void) {
    NSString *jb = SPKJailbreakRoot();
    NSMutableArray *roots = [NSMutableArray array];
    if (jb.length) [roots addObject:jb];
    [roots addObject:@"/var/jb"];
    [roots addObject:@""];
    for (NSString *r in roots) {
        if (Sk1nSpawn([r stringByAppendingString:@"/usr/bin/sbreload"], @[])) return YES;
    }
    for (NSString *r in roots) {
        if (Sk1nSpawn([r stringByAppendingString:@"/usr/bin/killall"], @[@"-9", @"SpringBoard"])) return YES;
    }
    return NO;
}
