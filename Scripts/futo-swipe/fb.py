"""Minimal schema-driven flatbuffer reader (python stdlib) for ExecuTorch .pte + XNNPACK blobs."""
import struct


class T:
    """Table view."""

    def __init__(self, buf, pos):
        self.buf = buf
        self.pos = pos
        so = struct.unpack_from('<i', buf, pos)[0]
        self.vt = pos - so
        self.vtsize = struct.unpack_from('<H', buf, self.vt)[0]

    def _off(self, slot):
        o = 4 + 2 * slot
        if o >= self.vtsize:
            return 0
        return struct.unpack_from('<H', self.buf, self.vt + o)[0]

    def scalar(self, slot, fmt, default=0):
        o = self._off(slot)
        if not o:
            return default
        return struct.unpack_from('<' + fmt, self.buf, self.pos + o)[0]

    def _ind(self, slot):
        o = self._off(slot)
        if not o:
            return None
        p = self.pos + o
        return p + struct.unpack_from('<I', self.buf, p)[0]

    def table(self, slot):
        p = self._ind(slot)
        return None if p is None else T(self.buf, p)

    def string(self, slot):
        p = self._ind(slot)
        if p is None:
            return None
        n = struct.unpack_from('<I', self.buf, p)[0]
        return self.buf[p + 4:p + 4 + n].decode('utf-8', 'replace')

    def vec_raw(self, slot):
        p = self._ind(slot)
        if p is None:
            return None, 0
        n = struct.unpack_from('<I', self.buf, p)[0]
        return p + 4, n

    def vec_scalar(self, slot, fmt):
        p, n = self.vec_raw(slot)
        if p is None:
            return []
        sz = struct.calcsize('<' + fmt)
        return list(struct.unpack_from('<%d%s' % (n, fmt), self.buf, p)) if n else []

    def vec_bytes(self, slot):
        p, n = self.vec_raw(slot)
        if p is None:
            return b''
        return bytes(self.buf[p:p + n])

    def vec_table(self, slot):
        p, n = self.vec_raw(slot)
        if p is None:
            return []
        out = []
        for i in range(n):
            q = p + 4 * i
            out.append(T(self.buf, q + struct.unpack_from('<I', self.buf, q)[0]))
        return out

    def vec_string(self, slot):
        p, n = self.vec_raw(slot)
        out = []
        for i in range(n or 0):
            q = p + 4 * i
            s = q + struct.unpack_from('<I', self.buf, q)[0]
            m = struct.unpack_from('<I', self.buf, s)[0]
            out.append(self.buf[s + 4:s + 4 + m].decode())
        return out


def root(buf, off=0):
    return T(buf, off + struct.unpack_from('<I', buf, off)[0])
