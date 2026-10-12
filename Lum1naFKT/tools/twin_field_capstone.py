#!/usr/bin/env python3
"""Twin FIELD# capstone: 21D50 IOGPUFamily vs 23F77 IOGPUFamily.

Parses MH_FILESET, disassembles only com.apple.iokit.IOGPUFamily TEXT.
Confirms SysMemory MD slot, QueueCreate word1 / stIn, queue namespace.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
from capstone.arm64 import ARM64_OP_MEM, ARM64_OP_IMM, ARM64_OP_REG

KC_21D50 = Path(
    "/Users/kolby/Projects/lumina/research/iphone12_26.5/artifacts/12mini/"
    "kernelcache.decompressed/kernelcache.decompressed"
)
KC_23F77 = Path(
    "/Users/kolby/Projects/lumina/research/iphone12_26.5/artifacts/23F77/"
    "kernelcache.release.iphone13.decompressed"
)

MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_FILESET_ENTRY = 0x80000035

cs = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
cs.detail = True
cs.skipdata = True


def parse_header(data: bytes, base: int):
    mag, _ct, _cs, ftype, ncmds, sizeofcmds, _fl, _rs = struct.unpack_from(
        "<IIIIIIII", data, base
    )
    if mag != MH_MAGIC_64:
        raise ValueError("not macho64")
    return ftype, ncmds, sizeofcmds


def iter_lcs(data: bytes, base: int):
    ftype, ncmds, sizeofcmds = parse_header(data, base)
    off = base + 32
    end = min(base + 32 + sizeofcmds, len(data))
    for _ in range(ncmds):
        if off + 8 > end:
            break
        cmd, csz = struct.unpack_from("<II", data, off)
        if csz < 8 or off + csz > len(data):
            break
        yield cmd, csz, off
        off += csz


class Kext:
    def __init__(self, data: bytes, name: str, fileoff: int, vmaddr: int):
        self.data = data
        self.name = name
        self.fileoff = fileoff
        self.vmaddr = vmaddr
        self.segments = []  # (nm, va, fo, fs)
        for cmd, csz, off in iter_lcs(data, fileoff):
            if cmd == LC_SEGMENT_64 and csz >= 72:
                nm = data[off + 8 : off + 24].split(b"\0", 1)[0].decode("latin1")
                va, vs, fo, fs = struct.unpack_from("<QQQQ", data, off + 24)
                self.segments.append((nm, va, fo, fs))

    def text(self) -> list[tuple[int, bytes]]:
        out = []
        for nm, va, fo, fs in self.segments:
            if fs < 0x40:
                continue
            if nm in ("__TEXT_EXEC", "__text") or nm.endswith("__text"):
                out.append((va, self.data[fo : fo + fs]))
        return out

    def cstrings(self) -> bytes:
        for nm, va, fo, fs in self.segments:
            if nm in ("__TEXT", "__cstring", "__TEXT_EXEC"):
                pass
        # whole kext span is enough for find
        spans = []
        for nm, va, fo, fs in self.segments:
            spans.append((fo, fo + fs, va))
        return spans

    def va_to_off(self, va: int) -> int | None:
        for _nm, va0, fo, fs in self.segments:
            if va0 <= va < va0 + fs:
                return fo + (va - va0)
        return None

    def off_to_va(self, off: int) -> int | None:
        for _nm, va, fo, fs in self.segments:
            if fo <= off < fo + fs:
                return va + (off - fo)
        return None

    def func_start(self, addr: int, back: int = 0x2000) -> int | None:
        off = self.va_to_off(addr)
        if off is None:
            return None
        lo = max(off - back, self.fileoff)
        for b in range(off, lo, -4):
            w = struct.unpack_from("<I", self.data, b)[0]
            if w in (0xD503233F, 0xD503231F):
                return self.off_to_va(b)
        return None


def load_iogpu(path: Path) -> tuple[bytes, Kext, str]:
    data = path.read_bytes()
    ident = "unknown"
    i = data.find(b"Darwin Kernel Version")
    if i >= 0:
        ident = data[i : i + 140].split(b"\0", 1)[0].decode("latin1", "replace")
    iogpu = None
    for cmd, csz, off in iter_lcs(data, 0):
        if cmd != LC_FILESET_ENTRY or csz < 32:
            continue
        vmaddr, fileoff = struct.unpack_from("<QQ", data, off + 8)
        stroff = struct.unpack_from("<I", data, off + 24)[0]
        name = data[off + stroff : data.find(b"\0", off + stroff)].decode()
        if name == "com.apple.iokit.IOGPUFamily":
            iogpu = Kext(data, name, fileoff, vmaddr)
            break
    if iogpu is None:
        raise SystemExit(f"no IOGPUFamily in {path}")
    return data, iogpu, ident


def xref(kext: Kext, needle: bytes, max_refs: int = 6) -> tuple[int | None, list[int]]:
    off = kext.data.find(needle, kext.fileoff)
    if off < 0:
        return None, []
    sva = kext.off_to_va(off)
    refs = []
    for tva, code in kext.text():
        adrp: dict[int, int] = {}
        for ins in cs.disasm(code, tva):
            try:
                if ins.mnemonic == "adrp" and ins.operands:
                    adrp[ins.operands[0].reg] = ins.operands[1].imm
                    continue
                if ins.mnemonic in ("add", "ldr") and ins.operands:
                    if ins.mnemonic == "add" and len(ins.operands) >= 3:
                        base, imm = ins.operands[1].reg, ins.operands[2].imm
                    elif ins.mnemonic == "ldr" and ins.operands[1].type == ARM64_OP_MEM:
                        m = ins.operands[1].mem
                        base, imm = m.base, m.disp
                    else:
                        continue
                    if sva is not None and base in adrp and (
                        (adrp[base] + imm) & 0xFFFFFFFFFFFFFFFF
                    ) == sva:
                        refs.append(ins.address)
                        if len(refs) >= max_refs:
                            return sva, refs
                if ins.operands and ins.operands[0].type == ARM64_OP_REG:
                    adrp.pop(ins.operands[0].reg, None)
            except Exception:
                continue
    return sva, refs


def dump_window(kext: Kext, addr: int, before: int = 0x28, after: int = 0x60) -> None:
    off = kext.va_to_off(addr - before)
    if off is None:
        print(f"    (unmap {addr:#x})")
        return
    blob = kext.data[off : off + before + after]
    for ins in cs.disasm(blob, addr - before):
        mark = "  <==" if ins.address == addr else ""
        print(f"    {ins.address:#x}: {ins.mnemonic:8s} {ins.op_str}{mark}")


def scan_fn(kext: Kext, fn: int, disps: set[int], imms: set[int], limit: int = 0xA00):
    off = kext.va_to_off(fn)
    if off is None:
        return {}, []
    blob = kext.data[off : off + limit]
    mop: dict[int, list[str]] = {d: [] for d in disps}
    ih: list[str] = []
    for ins in cs.disasm(blob, fn):
        if ins.mnemonic == "ret":
            break
        try:
            if ins.mnemonic.startswith(("ldr", "str", "ldur", "stur")):
                for op in ins.operands:
                    if op.type == ARM64_OP_MEM and op.mem.disp in disps:
                        mop[op.mem.disp].append(
                            f"{ins.mnemonic} {ins.op_str} @{ins.address:#x}"
                        )
            for op in ins.operands:
                if op.type == ARM64_OP_IMM and op.imm in imms:
                    ih.append(f"{ins.mnemonic} {ins.op_str} @{ins.address:#x}")
        except Exception:
            continue
    return mop, ih


def analyze(label: str, path: Path) -> None:
    print(f"\n======== {label} ========")
    data, kext, ident = load_iogpu(path)
    print(ident)
    print(
        f"IOGPUFamily fileoff={kext.fileoff:#x} vmaddr={kext.vmaddr:#x} "
        f"segs={[(n, hex(va), hex(fs)) for n, va, fo, fs in kext.segments]}"
    )
    needles = [
        ("qcreate", b"Invalid newCommandQueueArgsSize"),
        ("qcreate2", b"newCommandQueueArgsSize"),
        ("qfail", b"newCommandQueue failed"),
        ("qns", b"failed to add into name space"),
        ("detached", b"Not detached"),
        ("newmd", b"Failed to make new descriptor"),
        ("tex", b"allocIOGPUResource failed to alloc texture object"),
        ("sysmem", b"IOGPUSysMemory"),
    ]
    fns: dict[str, int | None] = {}
    for key, n in needles:
        sva, refs = xref(kext, n)
        print(f"\n-- {key} {n!r} --")
        if sva is None:
            print("  missing")
            fns[key] = None
            continue
        print(f"  str {sva:#x}  refs {[hex(r) for r in refs]}")
        if not refs:
            fns[key] = None
            continue
        fn = kext.func_start(refs[0])
        fns[key] = fn
        print(f"  fn {hex(fn) if fn else '??'}")
        dump_window(kext, refs[0])

    qfn = fns.get("qcreate") or fns.get("qcreate2") or fns.get("qfail") or fns.get("qns")
    if qfn:
        print(f"\n  [QueueCreate FIELD#] fn {qfn:#x}")
        mop, ih = scan_fn(
            kext,
            qfn,
            {0x88, 0x120, 0x38, 0x408, 0x410, 0x550, 0x558, 0x2c, 0xf8},
            {0x408, 0x410, 0x558, 0x550, 0xAB, 0x4F, 0x88},
        )
        for d, xs in mop.items():
            if xs:
                print(f"    mem #0x{d:x}: " + " | ".join(xs[:8]))
        if ih:
            print("    imms: " + " ; ".join(ih[:16]))

    tfn = fns.get("tex")
    if tfn:
        print(f"\n  [withMemoryDescriptor MD slot] fn {tfn:#x}")
        mop, _ = scan_fn(kext, tfn, {0x30, 0x38, 0x80, 0x88, 0x90, 0xb0}, {0x80, 0x90})
        for d, xs in mop.items():
            if xs:
                print(f"    mem #0x{d:x}: " + " | ".join(xs[:10]))

    dfn = fns.get("detached")
    if dfn:
        print(f"\n  [replace_backing MD slot] fn {dfn:#x}")
        mop, _ = scan_fn(kext, dfn, {0x30, 0x38, 0x80, 0x88, 0x90}, {0x80, 0x90})
        for d, xs in mop.items():
            if xs:
                print(f"    mem #0x{d:x}: " + " | ".join(xs[:10]))


def main() -> int:
    analyze("21D50 12mini 17.3", KC_21D50)
    analyze("23F77 A14 26.5", KC_23F77)
    print(
        "\nTWIN: P007/23F77 uses SysMemory MD +0x90 (Ghidra getter/replace). "
        "21D50 live FKT dumps +0x80 as MOVE. QueueCreate word1 is "
        "IOGPUCommandQueue+0x558 (index 0xab), looked up by qid in the "
        "device namespace — never the device object itself."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
