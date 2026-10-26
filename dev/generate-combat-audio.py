"""Generate original short PCM effects, reproducibly, without external assets."""
import math
import random
import struct
import wave
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / 'assets' / 'audio' / 'combat'
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050

def write(name, duration, make):
    rng = random.Random(513)
    values = []
    for i in range(int(duration * RATE)):
        t = i / RATE
        edge = min(1, t / .004) * min(1, (duration-t) / .015)
        values.append(int(max(-1, min(1, make(t, rng))) * edge * 27000))
    with wave.open(str(OUT / (name + '.wav')), 'wb') as output:
        output.setparams((1, 2, RATE, len(values), 'NONE', 'not compressed'))
        output.writeframes(struct.pack('<' + 'h'*len(values), *values))

write('swing', .14, lambda t,r: (r.uniform(-1,1)*.5 + math.sin(2*math.pi*(900*t-1800*t*t))*.12)*math.sin(math.pi*t/.14)**1.5)
write('hit', .10, lambda t,r: (math.sin(2*math.pi*(190*t-450*t*t))*.65+r.uniform(-1,1)*.28)*math.exp(-t*42))
write('crit', .18, lambda t,r: (math.sin(2*math.pi*(260*t-450*t*t))*.55+r.uniform(-1,1)*.4)*math.exp(-t*28))
print('Generated swing/hit/crit PCM effects')
