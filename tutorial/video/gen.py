#!/usr/bin/env python3
"""Generate index.html + assets/narration.wav from script.json + tts-manifest.json (stimmwerk parts)."""
import json, os, re, subprocess, wave, html, sys
import numpy as np
H = os.path.dirname(os.path.abspath(__file__))
SC = json.load(open(f'{H}/script.json'))
MAN = json.load(open(f'{H}/build/tts-manifest.json'))
P = MAN['paragraphs']
GAIN = 1.0  # stimmwerk parts are already at mix level; parts_gain_db is informational (applying it again clipped)
LEAD, TAIL, GAP = 0.8, 1.5, 0.75
GAPS = {'S04': [0.9, 1.3, 0.8], 'S09': [0.6, 1.4, 1.4, 2.8], 'S10': [0.8, 1.0, 1.0], 'S11': [0.9, 1.2, 1.4], 'S12': [1.2, 1.2], 'S07': [0.9, 1.0, 0.9],
        'S03': [0.8, 0.8], 'S08': [0.9, 1.0, 1.0], 'S05': [0.8, 0.8, 0.8], 'S06': [0.8], 'S13': [0.8, 1.2], 'S14': [1.0], 'S01': [0.6, 0.9], 'S02': [0.8, 0.9]}
SR = 24000
def rd(path):
    from scipy.io import wavfile
    sr,a=wavfile.read(path); a=a.astype(np.float32); return a if a.ndim==1 else a[:,0]
T = {}; caps = []; placed = []; t = 0.0; idx = 0
for s in SC:
    t0 = t; cur = t0 + LEAD; ls = []; es = []
    for k, ln in enumerate(s['lines']):
        p = P[idx]; d = p['duration']; assert abs(len(rd(f"{H}/assets/tts/{os.path.basename(p['file'])}")) / SR - d) < 0.05
        ls.append(round(cur, 3)); es.append(round(cur + d, 3)); placed.append((cur, os.path.basename(p['file'])))
        gap = GAPS.get(s['id'], [])[k] if k < len(GAPS.get(s['id'], [])) else GAP
        cur += d + (gap if k < len(s['lines']) - 1 else 0); idx += 1
    t1 = es[-1] + TAIL
    T[s['id']] = {'t0': round(t0, 3), 't1': round(t1, 3), 'l': ls, 'e': es}
    for k, ln in enumerate(s['lines']):
        nxt = ls[k + 1] if k + 1 < len(ls) else t1
        caps.append({'s': ls[k], 'e': round(min(es[k] + 0.5, nxt - 0.05) if k + 1 < len(ls) else es[k] + 0.6, 3), 'text': ln['cap']})
    t = t1
total = round(t + 0.3, 3)
T['caps'] = caps
# narration
buf = np.zeros(int(total * SR) + SR, dtype=np.float32)
for st, fn in placed:
    a = rd(f'{H}/assets/tts/{fn}') * GAIN; i = int(st * SR); buf[i:i + len(a)] += a
buf = np.clip(buf, -1, 1)
tmp = f'{H}/build/narr-raw.wav'
w = wave.open(tmp, 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((buf * 32767).astype('<i2').tobytes()); w.close()
subprocess.run(['ffmpeg', '-y', '-v', 'error', '-i', tmp, '-ar', '48000', '-ac', '1', f'{H}/assets/narration.wav'], check=True)
json.dump(T, open(f'{H}/build/times.json', 'w'), indent=1)
open(f'{H}/build/vidmin.txt', 'w').write(str(round(total / 60)))
fonts = open(f'{H}/assets/fonts/fonts.css').read()
css = open(f'{H}/src/style.css').read()
body = open(f'{H}/src/body.html').read()
def rep(m):
    sid, key = m.group(1), m.group(2)
    v = T[sid]; return str(v['t0'] if key == 'start' else round(v['t1'] - v['t0'], 3))
body = re.sub(r'\{\{(S\d+)\.(start|dur)\}\}', rep, body)
capsh = ''.join(f'<div class="cap clip" data-start="{c["s"]}" data-duration="{round(c["e"]-c["s"],3)}" data-track-index="9"><div class="in" id="cap{i}">{html.escape(c["text"])}</div></div>\n' for i, c in enumerate(caps))
js = open(f'{H}/src/anim.js').read().replace('__TIMES__', json.dumps({k: (v if k == 'caps' else {'t0': v['t0'], 't1': v['t1'], 'l': v['l'], 'e': v['e']}) for k, v in T.items()} | {'caps': [{'s': c['s'], 'e': c['e']} for c in caps]}))
out = f'''<!doctype html>
<html lang="de">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=1920, height=1080" />
<title>Schicksalsschlag Erklärvideo</title>
<script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
<style>
{fonts}
{css}
</style>
</head>
<body>
<div id="root" data-composition-id="main" data-start="0" data-width="1920" data-height="1080" data-duration="{total}">
{body}
{capsh}
<audio id="narr" src="assets/narration.wav" data-start="0" data-duration="{total}" data-track-index="10" data-volume="1"></audio>
</div>
<script>
{js}
</script>
</body>
</html>
'''
open(f'{H}/index.html', 'w').write(out)
print('total', total, 'scenes', {k: (v['t0'], v['t1']) for k, v in T.items() if k != 'caps'})
