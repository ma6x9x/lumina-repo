//
//  ANEYcraft.h — Lum1naFKT 0.8.0 twin module.
//
//  Ports the P007 P080 y-craft branch table to the 12 mini twin
//  (iPhone13,1 / 21D50 / Dopamine). TWIN MECHANISM ONLY — same rule as
//  the rest of FKT: CLASS / FIELD# / MECHANISM transfers to 23F77,
//  never KVAs, never offsets.
//
//  What it does (all in-process, NO KRW required):
//   1. Bundled models XVRC27_127in_1out + XVRC27_127inmin_1out (same
//      ABI as the P007 app: 127 Double rank-1 inputs, one output).
//   2. 412 IOSurfaces (candidates staged 0x00000000, capture staged
//      0x53535353), x_i = sids[i] so ALL 127 input records are live.
//   3. ENGAGEMENT GATE: min-of-20 All vs CpuOnly on model A.
//   4. READ-DOOR differential on model A: y==0.0 => ANE reads our wired
//      surfaces; y==fp16-serial-sum(sids) => client copies x values into
//      its own staging; y==double-sum => CPU fallback (request aborted).
//   5. WRITE DOOR on model B (y = MIN(sum, x_000) == sids[0]): predict1
//      sets prev y = sids[0]; predict2's output record sid = prev y =
//      OUR surface 0 -> ANE writes into it -> full surface scan.
//
//  Why this matters: on the twin these four branches are the SAME
//  mechanism questions P080 answers blind on 23F77. A twin answer is
//  ground truth (17.3 espresso / ANE driver), which the 23F77 probes
//  then confirm. Branch behavior that matches on BOTH builds is
//  mechanism; branch behavior that differs is version-specific —
//  either way the P080 log becomes interpretable instead of guessed.
//
//  Kernel-side record dumps (buffercache / request object walk) are
//  PENDING: FKT_21D50.h has no H11ANEIn offsets yet. When a Ghidra pass
//  on the 21D50 kernelcache pins them, the module gains a phase that
//  kreads the records around each predict.
//
//  Honesty: everything here is own-surface, own-process. No foreign
//  sid, no conversion, hasKread=NO hasKwrite=NO. A capture hit would be
//  an ANE write into OUR surface through the request path — the write
//  door shape, not KRW.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ANEYcraft : NSObject
/// Runs the full sequence, logs per line with F_FULLFSYNC to
/// /var/mobile/Documents/lum1na-fkt-ane.txt, returns the log body.
+ (NSString *)run;
+ (NSString *)dumpPath;
@end

NS_ASSUME_NONNULL_END