#!/usr/bin/env python3
"""So hai file `heap -s` (mẫu của ram-audit.sh): lớp tăng nhiều byte nhất.
  heapdiff.py <a.heap> <b.heap> [top=30]"""
import re, sys

def load(p):
    d, total = {}, 0
    for line in open(p, errors="replace"):
        m = re.match(r"\s*(\d+)\s+(\d+)\s+([\d.]+)\s+(.+?)\s{2,}(\S+)?\s*(\S+)?\s*$", line)
        if m and not line.strip().startswith("COUNT"):
            key = m.group(4).strip()
            c, b = d.get(key, (0, 0))
            d[key] = (c + int(m.group(1)), b + int(m.group(2)))
        m = re.match(r"All zones: (\d+) nodes \((\d+) bytes\)", line)
        if m: total = int(m.group(2))
    return d, total

a, ta = load(sys.argv[1]); b, tb = load(sys.argv[2])
top = int(sys.argv[3]) if len(sys.argv) > 3 else 30
print("heap total: %.2f MB -> %.2f MB (%+.2f)" % (ta / 1048576, tb / 1048576, (tb - ta) / 1048576))
rows = [(b.get(k, (0, 0))[1] - a.get(k, (0, 0))[1], b.get(k, (0, 0))[0] - a.get(k, (0, 0))[0], k) for k in set(a) | set(b)]
for db, dc, k in sorted(rows, reverse=True)[:top]:
    print("%+9.1f KB %+7d  %s" % (db / 1024, dc, k))
