/* Unslid 21D50 kernelcache (iPhone13,1 / xnu-10002.82.4~3).
   Live VA = unslid + (kbase - FKT_UNSLID_BASE).
   Do NOT use these numbers as 23F77 offsets. */
#pragma once

#define FKT_UNSLID_BASE          0xFFFFFFF007004000ULL
#define FKT_DC_UNSLID            0xFFFFFFF007874000ULL
#define FKT_DC_SIZE              0x4C8000ULL
#define FKT_DATA_UNSLID          0xFFFFFFF00A2A4000ULL
#define FKT_DATA_SIZE            0x210000ULL

#define FKT_STR_IOMD             0xFFFFFFF0070A155AULL
#define FKT_STR_GMD              0xFFFFFFF0070A1592ULL
#define FKT_STR_GMD_ZONE         0xFFFFFFF0070A15ACULL
#define FKT_STR_SYSMEM           0xFFFFFFF0075A8C9AULL
#define FKT_STR_IOSURF_CLIENT    0xFFFFFFF0075FCE48ULL
#define FKT_STR_DATA_KALLOC      0xFFFFFFF007045503ULL

/* Twin FIELD# — 21D50 IOGPUFamily (Ghidra kext open 2026-09-02) vs 23F77.
   Never paste 21D50 KVAs into P007. Match CLASS + FIELD# only.

   IOGPUSysMemory:
     21D50 getter IOGPUSysMemory_raw_MD_get_plus80 = *(obj+0x80)
     21D50 create stores MD at +0x80, length at +0x30, options at +0x88, arg at +0x90
     instSize 0xa8
     23F77 getter = *(obj+0x90); withMemoryDescriptor stores MD +0x90, zeros +0x80
     instSize 0xd8
   resource → SysMemory stays +0x28 on both.

   P010 QueueCreate copyout:
     21D50 s_new_command_queue: out[0]=qid, out[1]=queue[0xaa]=+0x550
     23F77: out[1]=queue[0xab]=+0x558  (MOVED +8 — P007 uses +0x558)
     qid stored at queue+0x420 (21D50 IOGPUCommandQueue_set_qid)
     namespace = *(device+0x88), arr = *(ns+0x10)
     21D50 has NO structIn 0x410 check (23F77 requires == 0x410). */
#define FKT_23F77_SYSMEM_DETACH_OFF  0x30u
#define FKT_23F77_SYSMEM_BYTECOUNT   0x38u
#define FKT_23F77_SYSMEM_VA_OFF      0x88u
#define FKT_23F77_SYSMEM_MD_OFF      0x90u
#define FKT_21D50_SYSMEM_MD_OFF      0x80u
#define FKT_21D50_SYSMEM_LEN_OFF     0x30u
#define FKT_21D50_QUEUE_WORD1_OFF    0x550u
#define FKT_23F77_QUEUE_WORD1_OFF    0x558u
#define FKT_21D50_QUEUE_QID_OFF      0x420u
#define FKT_QUEUE_NS_OFF             0x88u
