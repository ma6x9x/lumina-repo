# Lum1na-FKT — lab primitive testbed (0.9.0)

**12 mini (iPhone13,1 / 21D50 / Dopamine):** live kread for **CLASS / FIELD#** twin onto 23F77.  
**Not** a 23F77 kernel. Dumping 17.3 does not kread the hunt phone.

**A13 reference rig (iPhone12,1 / 18.6.2 / Dopamine 3.0):** second target. libkrw primitives from Dopamine; the 21D50 twin queries will report NOT 21D50 and the IOGPU FIELD# offsets must never be pasted cross-SKU. Dump + ANE y-craft run per-build.

**Hunt phone (iPhone13,2 / 23F77):** P007 oracles only unless this device itself is jailbroken (it is not).

**Map** in the app prints the 23F77 leftover catalog with no kread (43724/43722/43748/P009/CS/P022). Dump Now still runs Q1–Q7 on 21D50.

Never paste 21D50 live KVAs into P007.

## What’s in 0.7.1

**KC** button: mmap a *copy* of a decompressed kernelcache in `/var/mobile/Documents/` and HIT/MISS leftover strings (`owns_replaceable`, auto-prewiring, CheckandPrewire, slide error, i/o buffers). This is **not** mapping 26.5 as the live kernel. 17.3 tfp0 still reads 17.3 RAM.

```bash
scp artifacts/23F77/kernelcache.release.iphone13.decompressed \
  mobile@12mini:/var/mobile/Documents/kernelcache.release.iphone13.decompressed
```

No on-device LLM. Pattern HIT/MISS is the useful “ML-shaped” check.

## What’s in 0.7.0

- Leftover catalog header on every dump (`FKT_23F77.h`)
- App **Map** button — catalog only
- Twin FIELD# unchanged: SysMemory MD 21D50 `+0x80` / 23F77 `+0x90`; P010 `+0x550` / `+0x558`
- gzip debs still required on Dopamine 17.3
- No 254 fire, no #536 blob, no CS hop 1

Device: iPhone13,1 A14 **21D50**. Live VA = 21D50 unslid + slide. Match to 23F77 by **class name + instSize + vtable slot index**, never by KVA.

## What’s in 0.6.1

17.3 IOGPUFamily Ghidra + live dump loop for **26.5 FIELD#s**:

- **P010** looks up the **CommandQueue** in `*(device+0x88)` (qid at queue `+0x420`). Word1 is **`+0x550` on 21D50**, **`+0x558` on 23F77 / P007**. Does not dump the device object.
- **SysMemory** getter is `*(+0x80)` on 21D50 (instSize `0xa8`); 23F77 getter is `*(+0x90)` (instSize `0xd8`). Atlas labels 17.3 `+0x30` as length, not flags.
- **Shape-1** no longer counts variant B (`flags 0x11b` + `kernel_task` GPU windows at `0xffffffe8…`).

Never paste 21D50 live KVAs into P007. Twin **CLASS / FIELD# / FACTORY** only.

## What’s in 0.6.0

Diff workbench on the 12 mini. **Dump Now** still runs Q1–Q7, then:

- **SYSMEM ATLAS** — every interesting qword on each live `IOGPUSysMemory`. 23F77 MD at **+0x90**; 21D50 live **+0x80**.
- **PTR** lines — grep `^PTR ` for theories `IOGPUSYSMEM`, `64788`, `P010`, `IOSURFACE`.
- **Snap A / Snap B / Diff** — dump → Snap A → change state → dump → Snap B → Diff.

## What’s in 0.5.3

Locks the 0xb0 occupant field map from the 0.5.2 zone walk. Classifies each occupant as **WAR** (USER ranges), **KERN_WIN** (GPU/IOMMU page maps — not Shape-1), or **SHAPE1** (object-sized KERN only). Stops reprinting the same zone page. `vt_unslid` is canonical (no 48-bit truncate).

## What’s in 0.5.2

Walks the real `iokit.IOGeneralMemoryDescriptor` zone (`z_self`, `z_elem_offs`, pageq → 0xb0 grid). Prints a SHAPE line (class / vt_unslid / +0x20/+0x50/+0x60/+0x70). App Metal MDs that are not on that grid are labeled `live_NOT_GMD_ZONE`.

## What’s in 0.5.1

Same Q1–Q7 sheet as 0.5.0. Occupant scan no longer counts page-scan aliases (KERN “range” whose length is another kernel pointer) as Shape-1. Magazine walk skips the zone name cstring. Q7 samples a USER-range MD, not the first empty IOSurface.

## What’s in 0.5

Option B sheet on one Dump Now (12 mini / 21D50 kread):

1. `kern.osversion` must be **21D50**
2. IOGPUSysMemory hexdump — IOMD* is **+0x80** live (23F77 **+0x90**)
3. That IOMD: size 0xb0, `+0x20` flags, `+0x50` getLength, `+0x60` ranges, task qword vs kernel_task / our task
4. IOSurface **+0x30** → MD + PAC-stripped class name
5. Metal bytesNoCopy 0x80: resource+0x28 → SysMemory → MD
6. GMD zone magazine arrays + page scan — list kernel_task GMDs and VA/len
7. writeBytes/prepare dest class (USER MD pages → not W)

## What’s in 0.3

| Piece | What |
|-------|------|
| **Lum1naFKT** tweak | SpringBoard inject — auto-dump ~2s after respring; listens `com.lumina.fkt.dump` |
| **Lum1naFKT** app | Home-screen UI: **Dump Now**, **Reload**, **Copy**, nav **SB dump** |
| Dump file | Always `/var/mobile/Documents/lum1na-fkt-dump.txt` |

Dump Now runs KReader in-app **and** posts the SpringBoard notify (whichever process has libkrw/tfp0 wins the file).

## Build (gzip — required on Dopamine 17.3)

This Mac has no `dpkg-deb`. Theos `dm.pl` defaults to **lzma**, which Dopamine `dpkg` splits on unpack. The Makefile already sets gzip.

```bash
export THEOS=/Users/kolby/theos
export THEOS_PLATFORM_DEB_COMPRESSION_TYPE=gzip
cd ~/Projects/lumina/lum1na-fkt
make clean package
```

Use **only** `packages/com.kolbymaxx.lum1nafkt_0.6.1-*+debug_iphoneos-arm64.deb`.
Do **not** install `0.6.0-1` (lzma) or any `data.tar.lzma` deb.

Confirm gzip before copying:

```bash
python3 -c "import sys; d=open(sys.argv[1],'rb').read(); print('gzip' if b'data.tar.gz' in d else 'NOT gzip — do not install')" packages/com.kolbymaxx.lum1nafkt_0.6.1-*+debug_iphoneos-arm64.deb
```

## Pull dumps for the Mac agent

The 12 mini is `root@192.168.1.231` (key auth, uid 0). Same LAN.

```bash
cd ~/Projects/lumina/lum1na-fkt
./pull.sh
# → pulled/lum1na-fkt-dump.txt
# → ~/Desktop/lumina_primitives/fkt_pull/
```

Then tell the agent to read `lum1na-fkt/pulled/lum1na-fkt-dump.txt`.

## Install

```bash
./deploy.sh
# or Filza: dpkg -i … && killall -9 SpringBoard && uicache
```

After install you should see a **Lum1naFKT** icon. Open → **Dump Now** → **Copy** (or AirDrop the txt).

## If backend=none

Need libkrw or tfp0 on the jailbreak. App entitlements allow no-container; SpringBoard path is often more reliable — use nav **SB dump**, wait 2s, **Reload**.

## Not this build

Kernel prologue hooks, PPL PTE writes, pasting 21D50 KVAs into P007 / 23F77.
