/* 23F77 leftover MAP for Lum1naFKT dumps.
   FIELD# / class only. Never treat 21D50 live KVAs as these.
   Hunt phone iPhone13,2 26.5 — this header is a catalog, not a trigger. */
#pragma once

#define FKT_F77_SYSMEM_MD_OFF        0x90u
#define FKT_F77_QUEUE_WORD1_OFF      0x558u
#define FKT_F77_QUEUE_CREATE_STIN    0x410u
#define FKT_F77_NS_OFF               0x88u
#define FKT_F77_ANE_TABLE            0x820u
#define FKT_F77_ANE_NEIGHBOR         0x3e0u
#define FKT_F77_FILL_CAP             0u
#define FKT_F77_ACC_CLAMP            0u
#define FKT_F77_PATTERN_100000001    0x100000001ULL

#if defined(__OBJC__)
#import <Foundation/Foundation.h>
static inline NSString *FKTLeftoverCatalog(void) {
    return @"=== 23F77 LEFTOVER CATALOG (MAP — FKT 0.7) ===\n"
           @"Hunt: iPhone13,2 A14 26.5 23F77 xnu-12377.122.4. Twin 12 mini = 21D50 CLASS/FIELD# only.\n"
           @"12 mini JB: useful for zone/MD dumps on 17.3. NOT live kread of 23F77 kernel.\n"
           @"\n"
           @"FIELD#  SysMemory MD +0x90  (21D50 +0x80)\n"
           @"        P010 word1 queue+0x558  (21D50 +0x550)  QueueCreate stIn 0x410\n"
           @"        ns *(device+0x88)  43805 dest table[qid]\n"
           @"\n"
           @"43724 v5 STORE phystokv(PPN<<14)+acc  slide_page 0xfffffff009f1f204\n"
           @"        NO acc>0x3FF8 on F77. G90 clamps. pager 0x9f20320. #536 errno 22 this IPA.\n"
           @"43722 v2/v4 info[2] u16 LOAD — feeds WRITE on page. NOT usermode kread. NOT v5.\n"
           @"43748 CheckandPrewire 0x874c070 fill uncapped then mmap cmp #0x80 THEN IOFreeType.\n"
           @"        n>=0xc1 may hit NEXT 3072. Pattern {sid, u32, 0x100000001}. Neighbor UNNAMED.\n"
           @"        G71+ auto-prewiring cap 0x80. P045 v6 candidate hex; v7 header scan FALSE.\n"
           @"43805 P040 D PASS. P009 F ≠ W. CS hop 1 EINVAL. MIL compile FAIL. DataVault no.\n"
           @"P022GC benign 315; ../ exists=0. 64740 listed fixed 26.6.\n"
           @"Apple 26.5.2 (Jun 29) patches 43722/43724/39868 — hunt 23F77 is BEFORE that.\n"
           @"NO 254 fire. NO #536 blob. NOT [1].\n";
}
#endif
