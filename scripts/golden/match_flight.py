"""Match captured flight frames (autoplay PNGs) to decoded HNM clip frames.

usage: match_flight.py DUNE.DAT FRAMES_DIR FPS T0 T1 [sky index]
Prints, per captured frame, the best clip:frame and its error.
"""
import sys, glob
import numpy as np
from PIL import Image
import dunedat

dat, frames_dir, fps, t0, t1 = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
sky = int(sys.argv[6]) if len(sys.argv) > 6 else 1
arc = dunedat.Archive(dat)
start, colours = dunedat.sky_record(arc.read('SKYDN.HSQ'), sky)
CLIPS = ['MNT1', 'MNT2', 'MNT3', 'MNT4', 'MTG1', 'MTG2', 'MTG3', 'SIET', 'PALACE', 'FORT', 'DFL2', 'PLANT']
S = 4  # compare at 80x38 (rows 0..151), minimap corner masked
mask = np.ones((152 // S, 320 // S), bool)
mask[:80 // S, 190 // S:] = False

def small(rgb):
    a = rgb[:152].reshape(152 // S, S, 320 // S, S, 3).mean(axis=(1, 3))
    return a

refs, names = [], []
for c in CLIPS:
    if c + '.HNM' not in arc.entries:
        continue
    h = dunedat.Hnm(arc.read(c + '.HNM'))
    pal = [p if p else (0, 0, 0) for p in h.palette]
    for i, col in enumerate(colours):
        pal[start + i] = col
    lut = np.array(pal, np.float32)
    n = 0
    for scr in h.frames():
        idx = np.frombuffer(scr, np.uint8).reshape(200, 320)
        refs.append(small(lut[idx])); names.append(f'{c}:{n}'); n += 1
    print(f'# {c}: {n} frames', file=sys.stderr)
refs = np.stack(refs)
fs = sorted(glob.glob(frames_dir + '/*.png'))
last = None
for i, f in enumerate(fs):
    t = i / fps
    if t < t0 or t > t1:
        continue
    cap = small(np.asarray(Image.open(f).convert('RGB').resize((320, 200), Image.NEAREST), np.float32))
    err = np.abs(refs - cap).mean(axis=3)[:, mask].mean(axis=1)
    k = int(err.argmin())
    if names[k] != last:
        print(f'{t:7.2f} {names[k]:10s} err {err[k]:5.1f}')
        last = names[k]
