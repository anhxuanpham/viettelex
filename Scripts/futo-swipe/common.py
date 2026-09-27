"""Tiện ích chung (python stdlib) cho Scripts/futo-swipe: nội suy tuyến tính, greedy CTC."""
LETTERS = [chr(97 + i) for i in range(26)]


def interp(xs, xp, fp):
    """Như numpy.interp (xp tăng dần), kẹp hai đầu."""
    out = []
    j = 0
    n = len(xp)
    for x in xs:
        if x <= xp[0]:
            out.append(fp[0])
            continue
        if x >= xp[-1]:
            out.append(fp[-1])
            continue
        while j < n - 2 and xp[j + 1] < x:
            j += 1
        while j > 0 and xp[j] > x:
            j -= 1
        x0, x1 = xp[j], xp[j + 1]
        t = (x - x0) / (x1 - x0) if x1 > x0 else 0.0
        out.append(fp[j] + t * (fp[j + 1] - fp[j]))
    return out


def linspace(a, b, n):
    if n == 1:
        return [a]
    return [a + (b - a) * i / (n - 1) for i in range(n)]


def greedy(logem, nclass):
    """Greedy CTC: argmax mỗi bước, gộp lặp, bỏ blank (cột cuối)."""
    out, prev = [], -1
    for t in range(len(logem) // nclass):
        row = logem[t * nclass:(t + 1) * nclass]
        c = max(range(nclass), key=lambda i: row[i])
        if c != prev and c != nclass - 1:
            out.append(LETTERS[c])
        prev = c
    return ''.join(out)
