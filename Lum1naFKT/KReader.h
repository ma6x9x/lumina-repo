#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/// Phase 1 live kread on 12 mini iOS 17.3 / 21D50.
/// Offsets from this dump are 21D50 until a 26.5 KC bridge says otherwise.
@interface KReader : NSObject

+ (instancetype)shared;

/// Always `/var/mobile/Documents/lum1na-fkt-dump.txt` (shared by tweak + app).
+ (NSString *)dumpPath;

- (BOOL)openKRW;
- (NSString *)backendName;
- (uint64_t)kbase;

- (BOOL)kread:(uint64_t)addr into:(void *)buf size:(size_t)size;
- (uint64_t)kread64:(uint64_t)addr;
- (uint32_t)kread32:(uint64_t)addr;
- (uint16_t)kread16:(uint64_t)addr;

// KRW wrappers for planting artificial state
- (BOOL)kwrite:(uint64_t)addr from:(void *)buf size:(size_t)size;
- (BOOL)kwrite32:(uint64_t)addr val:(uint32_t)val;
- (BOOL)kwrite64:(uint64_t)addr val:(uint64_t)val;

/// Full workbench dump (classes + strings + IOSurface + 26.5 question sheet).
/// Call only when already uid 0 (or from the root helper).
- (NSString *)runPhase1;

/// Prefer root helper (`lum1na-fkt-dump`) — Dopamine KRW needs uid 0.
/// Spawns with setuid bit and/or persona; returns dump file contents.
+ (NSString *)runDumpPreferringRoot;

/// App (mobile) mints IOSurfaces before spawning root helper — Create fails as root CLI.
+ (NSUInteger)mintSurfacesForHelper;
+ (void)releaseMintedSurfaces;

/// 23F77 leftover MAP (no kread). Always safe to print on any SKU.
+ (NSString *)leftoverCatalog;

/// mmap a local decompressed KC (not live 26.5 RAM). Scan leftover strings → unslid VA.
/// Looks in /var/mobile/Documents/kernelcache.release.iphone13.decompressed (and 23F77/23G90 names).
+ (NSString *)scanLocalKernelcache;

/// Snapshot / diff of PTR/SYSMEM/OCC/SHAPE lines (no extra kread).
+ (NSString *)snapAPath;
+ (NSString *)snapBPath;
+ (NSString *)runSnapA;
+ (NSString *)runSnapB;
+ (NSString *)runDiff;

// Unlocked Primitive Probes
- (NSString *)runP005JITDowngrade;
- (NSString *)run65349IOPLLeak;

@end

NS_ASSUME_NONNULL_END