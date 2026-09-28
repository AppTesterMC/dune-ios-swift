"""Cryo sprite sheets (HSQ): 4-bit frames, plain or RLE, and 8-bit ones."""
import numpy as np, dunedat

def frames(data):
    d = data
    w = lambda o: d[o] | d[o + 1] << 8
    fio = w(0); count = w(fio) // 2
    out = {}
    for i in range(count):
        fo = fio + w(fio + 2 * i)
        if fo + 4 > len(d) or w(fo) == 0:
            continue
        w0 = w(fo); w1 = w(fo + 2); flags = w0 >> 8 & 0xFE; W = w0 & 0x1ff; H = w1 & 0xff; po = w1 >> 8
        if W == 0 or H == 0 or W > 320:
            continue
        q = fo + 4; comp = flags & 0x80; bpr = (W + 1) // 2; bpr += bpr % 2
        px = np.full((H, W), -1, np.int16)
        try:
            for y in range(H):
                row = []
                if comp:
                    while len(row) < bpr * 2:
                        c = d[q]; q += 1
                        if c & 0x80:
                            n = 257 - c; v = d[q]; q += 1; row += [v & 15, v >> 4] * n
                        else:
                            for k in range(c + 1):
                                v = d[q]; q += 1; row += [v & 15, v >> 4]
                else:
                    for k in range(bpr):
                        v = d[q]; q += 1; row += [v & 15, v >> 4]
                for x in range(W):
                    if row[x]:
                        px[y, x] = row[x] + po
        except IndexError:
            continue
        out[i] = px
    return out
