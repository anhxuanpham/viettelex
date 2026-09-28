#!/usr/bin/env python3
"""hprof-summary.py — tóm tắt heap dump Android (không cần MAT/LeakCanary).

  adb shell am dumpheap -g com.viettelex.android /data/local/tmp/vt.hprof   (-g = GC trước khi dump)
  adb pull /data/local/tmp/vt.hprof && hprof-conv vt.hprof vt-std.hprof
  hprof-summary.py vt-std.hprof [--top 30] [--filter com.viettelex]
  hprof-summary.py vt-std.hprof --referrers com.viettelex.android.ime.VietTelexIME

In: số instance + shallow size theo lớp (mảng primitive gộp theo kiểu). hprof-conv bỏ thông tin
heap nên số gồm cả zygote/boot image (lớp framework) — so sánh TƯƠNG ĐỐI giữa 2 dump.
--referrers: ai (lớp nào / GC root nào) đang trỏ tới từng instance của lớp — dò rò rỉ
(VietTelexIME/KeyboardView > 1 instance sau GC = có tham chiếu giữ lại).
"""
import struct, argparse
from collections import defaultdict

PSIZE = {2: 0, 4: 1, 5: 2, 6: 4, 7: 8, 8: 1, 9: 2, 10: 4, 11: 8}
PNAME = {4: 'boolean', 5: 'char', 6: 'float', 7: 'double', 8: 'byte', 9: 'short', 10: 'int', 11: 'long'}
ROOTS = {0xff: 'unknown', 0x01: 'jni-global', 0x02: 'jni-local', 0x03: 'java-frame', 0x04: 'native-stack',
         0x05: 'sticky-class', 0x06: 'thread-block', 0x07: 'monitor', 0x08: 'thread-object',
         0x89: 'interned', 0x8a: 'finalizing', 0x8b: 'debugger', 0x8c: 'ref-cleanup', 0x8d: 'vm-internal',
         0x8e: 'jni-monitor', 0x90: 'unreachable'}


def walk(data, on):
    """Gọi on(kind, ...) cho: 'string', 'class', 'root', 'cdump', 'inst', 'oarr', 'parr'."""
    p = data.index(b'\0') + 1
    idsz = struct.unpack('>I', data[p:p + 4])[0]; p += 12
    rid = (lambda o: struct.unpack('>I', data[o:o + 4])[0]) if idsz == 4 else (lambda o: struct.unpack('>Q', data[o:o + 8])[0])
    n = len(data)
    while p < n:
        tag = data[p]; ln = struct.unpack('>I', data[p + 5:p + 9])[0]; body = p + 9; end = body + ln
        if tag == 0x01:
            on('string', rid(body), data[body + idsz:end].decode('utf-8', 'replace'))
        elif tag == 0x02:
            on('class', rid(body + 4), rid(body + 8 + idsz))
        elif tag in (0x0c, 0x1c):
            q = body
            while q < end:
                st = data[q]; q += 1
                if st in ROOTS:
                    on('root', ROOTS[st], rid(q))
                    q += {0xff: 0, 0x01: idsz, 0x02: 8, 0x03: 8, 0x08: 8, 0x04: 4, 0x06: 4, 0x8e: 8}.get(st, 0) + idsz
                elif st == 0xfe: q += 4 + idsz
                elif st == 0x20:
                    cid = rid(q); sup = rid(q + idsz + 4); q += idsz + 4 + 6 * idsz
                    isz = struct.unpack('>I', data[q:q + 4])[0]; q += 4
                    cp = struct.unpack('>H', data[q:q + 2])[0]; q += 2
                    for _ in range(cp):
                        t = data[q + 2]; q += 3 + (idsz if t == 2 else PSIZE[t])
                    sc = struct.unpack('>H', data[q:q + 2])[0]; q += 2
                    statics = []
                    for _ in range(sc):
                        t = data[q + idsz]
                        if t == 2: statics.append(rid(q + idsz + 1))
                        q += idsz + 1 + (idsz if t == 2 else PSIZE[t])
                    fc = struct.unpack('>H', data[q:q + 2])[0]; q += 2
                    ftypes = [data[q + i * (idsz + 1) + idsz] for i in range(fc)]; q += fc * (idsz + 1)
                    on('cdump', cid, sup, isz, statics, ftypes)
                elif st == 0x21:
                    oid = rid(q); cid = rid(q + idsz + 4); bl = struct.unpack('>I', data[q + 2 * idsz + 4:q + 2 * idsz + 8])[0]
                    b0 = q + 2 * idsz + 8; q = b0 + bl
                    on('inst', oid, cid, bl, (b0, q), rid, idsz)
                elif st == 0x22:
                    oid = rid(q); cnt = struct.unpack('>I', data[q + idsz + 4:q + idsz + 8])[0]; cid = rid(q + idsz + 8)
                    b0 = q + 2 * idsz + 8; q = b0 + cnt * idsz
                    on('oarr', oid, cid, cnt, (b0, q), rid, idsz)
                elif st in (0x23, 0xc3):
                    cnt = struct.unpack('>I', data[q + idsz + 4:q + idsz + 8])[0]; t = data[q + idsz + 8]
                    q += idsz + 9 + (cnt * PSIZE[t] if st == 0x23 else 0)
                    on('parr', t, cnt)
                else:
                    raise SystemExit(f'sub-tag lạ 0x{st:02x} @ {q - 1}')
        p = end


def root_paths(data, targets, cname):
    """Đồ thị ngược chính xác (theo kiểu field) → BFS từ mỗi target lên GC root gần nhất."""
    sup, ftypes, statics, kind = {}, {}, {}, {}
    def onA(k, *x):
        if k == 'cdump': sup[x[0]] = x[1]; ftypes[x[0]] = x[4]; statics[x[0]] = x[3]
    walk(data, onA)
    layout = {}
    def refoffs(cid, idsz):
        if cid in layout: return layout[cid]
        offs, o, c = [], 0, cid
        while c:
            for t in ftypes.get(c, []):
                if t == 2: offs.append(o)
                o += idsz if t == 2 else PSIZE[t]
            c = sup.get(c, 0)
        layout[cid] = offs; return offs
    rev = defaultdict(list); roots = {}
    def onB(k, *x):
        if k == 'root': roots.setdefault(x[1], x[0])
        elif k == 'cdump':
            kind[x[0]] = 'class ' + cname.get(x[0], '?')
            for s in x[3]: rev[s].append(x[0])
        elif k == 'inst':
            oid, cid, _, (b0, _e), rid, idsz = x
            kind[oid] = cname.get(cid, '?')
            for o in refoffs(cid, idsz):
                v = rid(b0 + o)
                if v: rev[v].append(oid)
        elif k == 'oarr':
            oid, cid, cnt, (b0, _e), rid, idsz = x
            kind[oid] = cname.get(cid, '?') + '[]'
            for i in range(cnt):
                v = rid(b0 + i * idsz)
                if v: rev[v].append(oid)
    walk(data, onB)
    for t in sorted(targets):
        prev = {t: None}; frontier = [t]; hit = None
        while frontier and hit is None:
            nxt = []
            for o in frontier:
                if o in roots: hit = o; break
                for r in rev.get(o, []):
                    if r not in prev:
                        # WeakReference không giữ sống — bỏ qua cạnh qua referent
                        if kind.get(r, '').endswith('WeakReference') or kind.get(r, '').endswith('SoftReference'): continue
                        prev[r] = o; nxt.append(r)
            frontier = nxt
        if hit is None:
            print(f'  0x{t:x}: KHÔNG tới được root (rác / chỉ Weak) — không rò rỉ'); continue
        chain = []; o = hit
        while o is not None: chain.append(kind.get(o, hex(o))); o = prev[o]
        print(f'  0x{t:x}: ROOT[{roots[hit]}] ' + ' → '.join(chain))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file'); ap.add_argument('--top', type=int, default=30)
    ap.add_argument('--filter'); ap.add_argument('--referrers')
    ap.add_argument('--path', action='store_true', help='với --referrers: in chuỗi tham chiếu ngắn nhất tới GC root')
    a = ap.parse_args()
    data = open(a.file, 'rb').read()
    strings, cname = {}, {}
    count = defaultdict(int); size = defaultdict(int)
    targets = set()

    def on1(kind, *x):
        if kind == 'string': strings[x[0]] = x[1]
        elif kind == 'class': cname[x[0]] = strings.get(x[1], '?')
        elif kind == 'inst':
            k = cname.get(x[1], '?'); count[k] += 1; size[k] += x[2] + 8
            if a.referrers and k == a.referrers: targets.add(x[0])
        elif kind == 'oarr':
            k = cname.get(x[1], '?') + '[]'; count[k] += 1; size[k] += x[2] * 4 + 16
        elif kind == 'parr':
            k = PNAME[x[0]] + '[]'; count[k] += 1; size[k] += x[1] * PSIZE[x[0]] + 16
    walk(data, on1)

    if not a.referrers:
        rows = sorted(size.items(), key=lambda kv: -kv[1])
        if a.filter: rows = [r for r in rows if a.filter in r[0]]
        print(f'tổng shallow {sum(size.values()) / 1024:.0f} KB, {sum(count.values())} object (gồm zygote/image)')
        for k, v in rows[:a.top]:
            print(f'{v / 1024:9.1f} KB  {count[k]:7d}  {k}')
        return

    print(f'{len(targets)} instance {a.referrers}')
    if a.path:
        return root_paths(data, targets, cname)
    refs = defaultdict(list)

    def scan(owner, rng, rid, idsz):
        b0, b1 = rng
        for o in range(b0, b1 - idsz + 1, 1 if idsz == 4 else 4):
            v = rid(o)
            if v in targets: refs[v].append(owner)

    def on2(kind, *x):
        if kind == 'root' and x[1] in targets: refs[x[1]].append('ROOT:' + x[0])
        elif kind == 'cdump':
            for s in x[3]:
                if s in targets: refs[s].append('STATIC:' + cname.get(x[0], '?'))
        elif kind == 'inst': scan(cname.get(x[1], '?'), x[3], x[4], x[5])
        elif kind == 'oarr': scan(cname.get(x[1], '?') + '[]', x[3], x[4], x[5])
    walk(data, on2)
    for t in sorted(targets):
        print(f'  0x{t:x}: ' + ', '.join(sorted(set(refs.get(t, ['(không ai — rác chưa thu)'])))))


if __name__ == '__main__':
    main()
