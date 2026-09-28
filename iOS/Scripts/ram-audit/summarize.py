#!/usr/bin/env python3
"""Tóm tắt mẫu footprint của ram-audit.sh: một dòng mỗi mốc, cột theo nhóm vùng nhớ.

  summarize.py <outdir> [--heap]   (--heap: thêm top lớp heap của mốc cuối)
Số là DIRTY (tính vào phys_footprint / jetsam), MB. mapped = trang sạch của file mmap.
"""
import os, re, sys, glob

UNIT = {"B": 1 / 1048576, "KB": 1 / 1024, "MB": 1, "GB": 1024}


def mb(s):
    v, u = s.split()
    return float(v) * UNIT[u]


GROUPS = [
    ("malloc", lambda c: c.startswith("Malloc")),
    ("CA", lambda c: c in ("CoreAnimation", "IOSurface", "IOKit", "IOAccelerator")),
    ("img", lambda c: c in ("CG Raster Data", "Image IO", "CG image")),
    ("dylibDATA", lambda c: c.startswith("__DATA") or c in ("__AUTH", "__AUTH_CONST", "__TPRO_CONST", "__OBJC_RW")),
    ("dyld", lambda c: "dyld" in c.lower()),
    ("stack", lambda c: c == "Stack"),
    ("pgtable", lambda c: c == "page table"),
]


def parse(path):
    rows, aux = {}, {}
    for line in open(path, errors="replace"):
        m = re.match(r"\s*([\d.]+ [KMG]?B)\s+([\d.]+ [KMG]?B)\s+([\d.]+ [KMG]?B)\s+(\d+)\s+(.+?)\s*$", line)
        if m:
            rows[m.group(5)] = (mb(m.group(1)), mb(m.group(2)))
        m = re.match(r"\s*(phys_footprint(?:_peak)?):\s+([\d.]+ [KMG]?B)", line)
        if m:
            aux[m.group(1)] = mb(m.group(2))
    return rows, aux


def main():
    out = sys.argv[1]
    files = sorted(glob.glob(os.path.join(out, "samples", "*.footprint")))
    hdr = ["mốc", "pid", "foot", "peak"] + [g for g, _ in GROUPS] + ["other", "mappedClean"]
    print(" | ".join(hdr))
    last = None
    for f in files:
        name = os.path.basename(f)[:-10]
        rows, aux = parse(f)
        if not rows:
            print(name, "(không đọc được)")
            continue
        pid = open(f[:-10] + ".pid").read().strip() if os.path.exists(f[:-10] + ".pid") else "?"
        used, cols = set(), []
        for g, pred in GROUPS:
            s = 0
            for c, (d, _) in rows.items():
                if c != "TOTAL" and c not in used and pred(c):
                    s += d
                    used.add(c)
            cols.append(s)
        other = sum(d for c, (d, _) in rows.items() if c not in used and c != "TOTAL")
        mapped = rows.get("mapped file", (0, 0))[1]
        print(" | ".join([name, pid, "%.1f" % aux.get("phys_footprint", 0), "%.1f" % aux.get("phys_footprint_peak", 0)]
                         + ["%.1f" % x for x in cols] + ["%.1f" % other, "%.1f" % mapped]))
        last = f
    if "--heap" in sys.argv and last:
        h = last[:-10] + ".heap"
        print("\nTop heap (%s):" % os.path.basename(h))
        start = False
        n = 0
        for line in open(h, errors="replace"):
            if "=====" in line:
                start = True
                continue
            if start and line.strip():
                print(line.rstrip())
                n += 1
                if n >= 25:
                    break


main()
