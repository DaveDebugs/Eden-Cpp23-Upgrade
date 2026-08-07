#!/usr/bin/env python3
"""Symbolized stack extractor for Eden crash dumps.

Reads a Windows minidump directly (no cdb/WinDbg needed) and symbolizes every
plausible return address against eden.pdb using dbghelp.dll from System32.

Strategy: rather than a formal stack walk (which needs a live process or a
memory-read callback), scan each thread's stack region for 8-byte values that
land inside the target module's code range, then symbolize each. That yields
the real frames plus some stale noise -- with symbol names attached the real
chain is usually obvious.

Usage:
    python dumpstack.py <dump.dmp> [--symdir DIR] [--all-threads]
"""
import argparse
import ctypes
import os
import struct
import sys
from ctypes import Structure, byref, c_ulong, c_ulonglong, c_void_p, c_wchar

MAX_SYM_NAME = 2000
SYMOPT_UNDNAME = 0x00000002
SYMOPT_DEFERRED_LOADS = 0x00000004
SYMOPT_LOAD_LINES = 0x00000010
SYMOPT_FAIL_CRITICAL_ERRORS = 0x00000200
SYMOPT_NO_PROMPTS = 0x00080000


class SYMBOL_INFOW(Structure):
    _fields_ = [
        ("SizeOfStruct", c_ulong),
        ("TypeIndex", c_ulong),
        ("Reserved", c_ulonglong * 2),
        ("Index", c_ulong),
        ("Size", c_ulong),
        ("ModBase", c_ulonglong),
        ("Flags", c_ulong),
        ("Value", c_ulonglong),
        ("Address", c_ulonglong),
        ("Register", c_ulong),
        ("Scope", c_ulong),
        ("Tag", c_ulong),
        ("NameLen", c_ulong),
        ("MaxNameLen", c_ulong),
        ("Name", c_wchar * MAX_SYM_NAME),
    ]


class IMAGEHLP_LINEW64(Structure):
    _fields_ = [
        ("SizeOfStruct", c_ulong),
        ("Key", c_void_p),
        ("LineNumber", c_ulong),
        ("FileName", ctypes.c_wchar_p),
        ("Address", c_ulonglong),
    ]


class Symbolizer:
    def __init__(self, symdir):
        self.dbghelp = ctypes.WinDLL("dbghelp.dll")
        self.handle = ctypes.c_void_p(0xED0BEEF)
        self.dbghelp.SymSetOptions(
            SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS | SYMOPT_LOAD_LINES
            | SYMOPT_FAIL_CRITICAL_ERRORS | SYMOPT_NO_PROMPTS
        )
        if not self.dbghelp.SymInitializeW(self.handle, ctypes.c_wchar_p(symdir), False):
            raise OSError("SymInitializeW failed: %d" % ctypes.GetLastError())

    def load_module(self, image_path, base, size):
        self.dbghelp.SymLoadModuleExW.restype = c_ulonglong
        return self.dbghelp.SymLoadModuleExW(
            self.handle, None, ctypes.c_wchar_p(image_path), None,
            c_ulonglong(base), c_ulong(size), None, c_ulong(0),
        )

    def resolve(self, addr):
        sym = SYMBOL_INFOW()
        sym.SizeOfStruct = ctypes.sizeof(SYMBOL_INFOW) - MAX_SYM_NAME * ctypes.sizeof(c_wchar)
        sym.MaxNameLen = MAX_SYM_NAME
        disp = c_ulonglong(0)
        name = None
        if self.dbghelp.SymFromAddrW(self.handle, c_ulonglong(addr), byref(disp), byref(sym)):
            name = "%s+0x%x" % (sym.Name, disp.value)
        line = IMAGEHLP_LINEW64()
        line.SizeOfStruct = ctypes.sizeof(IMAGEHLP_LINEW64)
        ldisp = c_ulong(0)
        src = None
        if self.dbghelp.SymGetLineFromAddrW64(self.handle, c_ulonglong(addr), byref(ldisp), byref(line)):
            try:
                src = "%s:%d" % (line.FileName, line.LineNumber)
            except Exception:
                src = None
        return name, src


MINIDUMP_SIGNATURE = 0x504D444D
ST_THREAD_LIST = 3
ST_MODULE_LIST = 4
ST_EXCEPTION = 6
ST_MEMORY64_LIST = 9


def parse_dump(path):
    with open(path, "rb") as f:
        blob = f.read()

    sig, ver, nstreams, streams_rva = struct.unpack_from("<IIII", blob, 0)
    if sig != MINIDUMP_SIGNATURE:
        raise ValueError("not a minidump")

    streams = {}
    for i in range(nstreams):
        stype, size, rva = struct.unpack_from("<III", blob, streams_rva + i * 12)
        streams[stype] = (size, rva)

    out = {"blob": blob, "modules": [], "threads": [], "mem64": [], "exception": None}

    if ST_MODULE_LIST in streams:
        _, rva = streams[ST_MODULE_LIST]
        count = struct.unpack_from("<I", blob, rva)[0]
        off = rva + 4
        for _ in range(count):
            base, size, _cs, _ts, name_rva = struct.unpack_from("<QIIII", blob, off)
            nlen = struct.unpack_from("<I", blob, name_rva)[0]
            name = blob[name_rva + 4: name_rva + 4 + nlen].decode("utf-16-le", "replace")
            out["modules"].append({"base": base, "size": size, "name": name})
            off += 108

    if ST_THREAD_LIST in streams:
        _, rva = streams[ST_THREAD_LIST]
        count = struct.unpack_from("<I", blob, rva)[0]
        off = rva + 4
        for _ in range(count):
            (tid, _s, _pc, _p, _teb, stack_start, stack_size,
             stack_rva, ctx_size, ctx_rva) = struct.unpack_from("<IIIIQQIIII", blob, off)
            out["threads"].append({
                "tid": tid, "stack_start": stack_start, "stack_size": stack_size,
                "stack_rva": stack_rva, "ctx_size": ctx_size, "ctx_rva": ctx_rva})
            off += 48

    if ST_MEMORY64_LIST in streams:
        _, rva = streams[ST_MEMORY64_LIST]
        nranges, base_rva = struct.unpack_from("<QQ", blob, rva)
        off = rva + 16
        cur = base_rva
        for _ in range(nranges):
            start, size = struct.unpack_from("<QQ", blob, off)
            out["mem64"].append({"start": start, "size": size, "file_off": cur})
            cur += size
            off += 16

    if ST_EXCEPTION in streams:
        _, rva = streams[ST_EXCEPTION]
        tid = struct.unpack_from("<I", blob, rva)[0]
        code, flags, nested, addr = struct.unpack_from("<IIQQ", blob, rva + 8)
        out["exception"] = {"tid": tid, "code": code, "address": addr}

    return out


def read_mem(dump, addr, size):
    for r in dump["mem64"]:
        if r["start"] <= addr < r["start"] + r["size"]:
            avail = min(size, r["start"] + r["size"] - addr)
            off = r["file_off"] + (addr - r["start"])
            return dump["blob"][off:off + avail]
    return b""


def thread_stack_bytes(dump, t):
    data = read_mem(dump, t["stack_start"], t["stack_size"])
    if data:
        return data
    if t["stack_rva"]:
        return dump["blob"][t["stack_rva"]:t["stack_rva"] + t["stack_size"]]
    return b""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("--symdir", default=r"P:\Programming Repositories\eden\build\bin")
    ap.add_argument("--module", default="eden.exe")
    ap.add_argument("--all-threads", action="store_true")
    ap.add_argument("--max-frames", type=int, default=40)
    ap.add_argument("--max-threads", type=int, default=4)
    args = ap.parse_args()

    print("dump    : %s" % args.dump)
    dump = parse_dump(args.dump)
    print("modules : %d   threads: %d   mem64 ranges: %d"
          % (len(dump["modules"]), len(dump["threads"]), len(dump["mem64"])))

    exc = dump["exception"]
    if exc:
        print("\n=== EXCEPTION ===")
        print("  code    : 0x%08X" % exc["code"])
        print("  address : 0x%016X" % exc["address"])
        print("  thread  : %d" % exc["tid"])
        for m in dump["modules"]:
            if m["base"] <= exc["address"] < m["base"] + m["size"]:
                print("  module  : %s+0x%X"
                      % (os.path.basename(m["name"]), exc["address"] - m["base"]))
                break

    focus = None
    for m in dump["modules"]:
        if os.path.basename(m["name"]).lower() == args.module.lower():
            focus = m
            break
    if not focus:
        print("\n!! module %s not found. present:" % args.module)
        for m in dump["modules"][:30]:
            print("   ", os.path.basename(m["name"]))
        return 2

    lo, hi = focus["base"], focus["base"] + focus["size"]
    print("\nfocus   : %s 0x%X-0x%X (%.1f MB)"
          % (os.path.basename(focus["name"]), lo, hi, focus["size"] / 1e6))

    sym = Symbolizer(args.symdir)
    local_image = os.path.join(args.symdir, os.path.basename(focus["name"]))
    if not os.path.exists(local_image):
        local_image = focus["name"]
    rv = sym.load_module(local_image, focus["base"], focus["size"])
    print("symbols : SymLoadModuleExW -> 0x%X %s"
          % (rv, "(0 = PDB not matched)" if rv == 0 else ""))

    threads = dump["threads"]
    if not args.all_threads and exc:
        ordered = ([t for t in threads if t["tid"] == exc["tid"]]
                   + [t for t in threads if t["tid"] != exc["tid"]])
    else:
        ordered = threads

    shown = 0
    for t in ordered:
        data = thread_stack_bytes(dump, t)
        if not data:
            continue
        hits = []
        for off in range(0, max(0, len(data) - 8), 8):
            val = struct.unpack_from("<Q", data, off)[0]
            if lo <= val < hi:
                hits.append(val)
        if not hits:
            continue

        frames, seen = [], set()
        for a in reversed(hits):
            if a in seen:
                continue
            seen.add(a)
            frames.append(a)
            if len(frames) >= args.max_frames:
                break

        marker = "   <-- EXCEPTION THREAD" if exc and t["tid"] == exc["tid"] else ""
        print("\n=== thread %d (%d candidate frames)%s" % (t["tid"], len(hits), marker))
        for a in frames:
            name, src = sym.resolve(a)
            if name:
                s = "  0x%016X  +0x%-8X %s" % (a, a - lo, name)
                if src:
                    s += "   [%s]" % src
                print(s)
            else:
                print("  0x%016X  +0x%-8X <no symbol>" % (a, a - lo))
        shown += 1
        if not args.all_threads and shown >= args.max_threads:
            print("\n(use --all-threads for the rest)")
            break

    return 0


if __name__ == "__main__":
    sys.exit(main())
