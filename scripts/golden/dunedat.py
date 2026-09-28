"""DUNE.DAT (CD) archive access, HSQ unpacking and HNM decoding.

Python port of SwiftDune's DuneArchive.swift and HnmPlayer.swift, for
comparing captures of the original game with our renderer.
"""
import struct


class Archive:
    def __init__(self, path):
        self.f = open(path, 'rb')
        count = struct.unpack('<H', self.f.read(2))[0]
        table = self.f.read(count * 25)
        self.entries = {}
        for i in range(count):
            e = table[i * 25:(i + 1) * 25]
            name = e[:16].split(b'\0')[0].decode('latin1').upper()
            size, offset = struct.unpack('<II', e[16:24])
            if name and name not in self.entries:
                self.entries[name] = (offset, size)

    def read(self, name):
        offset, size = self.entries[name.upper()]
        self.f.seek(offset)
        return self.f.read(size)


def unpack_hsq(packed, size):
    out = bytearray(size)
    o = p = bits = queue = 0

    def bit():
        nonlocal p, bits, queue
        if bits == 0:
            queue = packed[p] | packed[p + 1] << 8
            p += 2
            bits = 16
        b = queue & 1
        queue >>= 1
        bits -= 1
        return b

    def byte():
        nonlocal p
        p += 1
        return packed[p - 1]

    while True:
        if bit():
            out[o] = byte(); o += 1
            continue
        if bit():
            first, second = byte(), byte()
            count = first & 7
            offset = ((first >> 3) | (second << 5)) - 0x2000
            if count == 0:
                count = byte()
                if count == 0:
                    break
        else:
            count = bit() * 2 + bit()
            offset = byte() - 256
        count += 2
        s = o + offset
        for _ in range(count):
            out[o] = out[s]; o += 1; s += 1
    return bytes(out[:o])


def unpack_resource(data):
    """An .HSQ file: 6-byte header (size, 0, packed size, checksum)."""
    size = data[0] | data[1] << 8 | data[2] << 16
    return unpack_hsq(data[6:], size)


def rgb6(r, g, b):
    return ((r & 0x3F) << 2, (g & 0x3F) << 2, (b & 0x3F) << 2)


def sky_record(skydn, index):
    """SKYDN.HSQ's palette record `8 + index` (sunrise 16, day 1, sunset 6, night 3)."""
    d = unpack_resource(skydn)
    w = lambda o: d[o] | d[o + 1] << 8
    table = w(0)
    pos = table + w(table + 2 * (8 + index))
    start, count = d[pos + 4], d[pos + 5]
    return start, [rgb6(*d[pos + 6 + 3 * i:pos + 9 + 3 * i]) for i in range(count)]


class Hnm:
    W, H = 320, 200

    def __init__(self, data):
        self.d = data
        self.palette = [None] * 256
        self.begin()

    def w(self, o):
        return self.d[o] | self.d[o + 1] << 8

    def read_palette(self, block, size, pos):
        d = self.d
        while pos + 2 <= size:
            start, raw = d[block + pos], d[block + pos + 1]
            pos += 2
            if start == 0xFF and raw == 0xFF:
                return True
            if start == 0 and raw == 1:
                pos += 3
                continue
            count = 256 if raw == 0 else raw
            for i in range(count):
                self.palette[start + i] = rgb6(*d[block + pos:block + pos + 3])
                pos += 3
        return False

    def begin(self):
        self.screen = bytearray(self.W * self.H)
        size = self.w(0)
        self.read_palette(0, size, 2)
        self.offset = size

    def frames(self):
        """Yields the screen (320x200 indices) after each picture."""
        d = self.d
        while self.offset + 2 <= len(d):
            chunk = self.offset
            size = self.w(chunk)
            if size < 2:
                return
            self.offset += size
            pos = 2
            while pos + 4 <= size:
                block = chunk + pos
                tag = d[block:block + 2]
                bsize = self.w(block + 2)
                if tag in (b'sd', b'pl', b'pt', b'kl', b'mm'):
                    if tag == b'pl':
                        self.read_palette(block, bsize, 4)
                    pos += bsize
                    continue
                self.decode(block, size - pos)
                yield bytes(self.screen)
                break

    def decode(self, block, size):
        d = self.d
        header = self.w(block)
        width, height = header & 0x1FF, d[block + 2]
        transparent = d[block + 3] == 0xFF
        if width == 0 or height == 0:
            return
        body = d[block + 4:block + size]
        if header & 0x0200:
            unpacked = body[0] | body[1] << 8
            packed = body[3] | body[4] << 8
            body = unpack_hsq(body[6:packed], unpacked)
        x = y = 0
        if not header & 0x0400:
            x, y = struct.unpack('<HH', body[:4])
            body = body[4:]
        scale = 2 if (not transparent and width == self.W // 2) else 1
        rle = header & 0x8000
        p = 0
        for row in range(height):
            if rle:
                line = bytearray()
                while len(line) < width:
                    c = body[p]; p += 1
                    c = c - 256 if c > 127 else c
                    n = abs(c) + 1
                    if c < 0:
                        line += bytes([body[p]]) * n; p += 1
                    else:
                        line += body[p:p + n]; p += n
                line = line[:width]
            else:
                line = body[row * width:(row + 1) * width]
            for ry in range(scale):
                ty = (y + row) * scale + ry
                if ty >= self.H:
                    break
                base = ty * self.W
                for cx in range(width):
                    v = line[cx]
                    if transparent and v == 0:
                        continue
                    for rx in range(scale):
                        tx = (x + cx) * scale + rx
                        if tx < self.W:
                            self.screen[base + tx] = v
