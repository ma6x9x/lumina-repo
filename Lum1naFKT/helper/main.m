#import <Foundation/Foundation.h>
#import <stdio.h>
#import <unistd.h>
#import "KReader.h"

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        /* setuid bit / persona spawn → become real root before KRW. */
        if (geteuid() == 0 && getuid() != 0)
            setuid(0);
        fprintf(stderr, "lum1na-fkt-dump: uid=%u euid=%u\n", getuid(), geteuid());
        NSString *body = [[KReader shared] runPhase1];
        fprintf(stderr, "lum1na-fkt-dump: %lu bytes → %s\n",
                (unsigned long)body.length,
                [KReader dumpPath].fileSystemRepresentation);
        return (body.length > 0 && [[KReader shared] kbase] != 0) ? 0 : 2;
    }
}
