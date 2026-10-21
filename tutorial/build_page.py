#!/usr/bin/env python3
"""Build tutorial/index.html from index.src.html: inline images, expand annotated figures, oracle data, traits."""
import base64, io, json, html, math, os, re, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = os.path.join(HERE, 'img')
SRC = open(os.path.join(HERE, 'index.src.html'), encoding='utf-8').read()
ORACLE = json.load(open(os.path.join(HERE, 'oracle.json'), encoding='utf-8'))
TRAITS = json.load(open(os.path.expanduser('~/Projects/sl-pnp/handout/data/traits.json'), encoding='utf-8'))
FIGS = json.load(open(os.path.join(HERE, 'figures.json'), encoding='utf-8'))
VIDMIN = open(os.path.join(HERE, 'video', 'build', 'vidmin.txt')).read().strip() if os.path.exists(os.path.join(HERE, 'video', 'build', 'vidmin.txt')) else '4'


def jpeg_uri(path, q=80, maxw=1700):
    im = Image.open(path).convert('RGB')
    if im.width > maxw:
        im = im.resize((maxw, round(im.height * maxw / im.width)))
    b = io.BytesIO()
    im.save(b, 'JPEG', quality=q, optimize=True)
    return 'data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode(), im.size


def arrow(cx, cy, tx, ty, r=13):
    dx, dy = tx - cx, ty - cy
    d = math.hypot(dx, dy) or 1
    ux, uy = dx / d, dy / d
    sx, sy = cx + ux * r, cy + uy * r
    ex, ey = tx, ty
    hx, hy = ex - ux * 11, ey - uy * 11  # shaft ends before the head
    px, py = -uy, ux
    head = f'{ex:.1f},{ey:.1f} {hx + px * 6:.1f},{hy + py * 6:.1f} {hx - px * 6:.1f},{hy - py * 6:.1f}'
    return (f'<path class="ar" d="M{sx:.1f} {sy:.1f} L{hx:.1f} {hy:.1f}" pathLength="1"/>'
            f'<polygon class="ah" points="{head}"/>')


def fig(name):
    f = FIGS[name]
    used = set()
    x, y, w, h = f['view']
    parts = []
    for m in f['marks']:
        n = m['n']
        s = ''
        if 'box' in m:
            bx, by, bw, bh = m['box']
            s += f'<rect class="bx" x="{bx}" y="{by}" width="{bw}" height="{bh}"/>'
            cx, cy = m.get('cx', bx - 4), m.get('cy', by - 4)
            if 'tx' in m:
                s += arrow(cx, cy, m['tx'], m['ty'])
        else:
            cx, cy = m['cx'], m['cy']
            s += arrow(cx, cy, m['tx'], m['ty'])
        s += f'<g class="mkg" style="transform-box:fill-box;transform-origin:center"><circle class="mk" cx="{cx}" cy="{cy}" r="13"/><text class="mt" x="{cx}" y="{cy}">{n}</text></g>'
        parts.append(s)
    legend = ''.join(f'<li><b>{m["n"]}</b><span>{m["t"]}</span></li>' for m in f['marks'])
    img = f['img']
    alt = html.escape(f.get('alt', f['cap']))
    return (f'<figure class="shot{" wideimg" if f.get("wide") else ""}" data-r><div class="frame"><svg viewBox="{x} {y} {w} {h}" role="img" aria-label="{alt}">'
            f'<use href="#im-{img}"/>{"".join(parts)}</svg></div>'
            f'<figcaption>{f["cap"]}</figcaption><ol class="legend">{legend}</ol></figure>')


def traits_html():
    out = []
    names = [('positiv_klein', 'Vorteile klein (−2)', ''), ('positiv_gross', 'Vorteile groß (−4)', 'big'),
             ('negativ_klein', 'Nachteile klein (+2)', 'neg'), ('negativ_gross', 'Nachteile groß (+4)', 'neg big')]
    for k, title, cls in names:
        out.append(f'<h4 style="margin:14px 0 4px">{title}</h4><div class="pills">')
        for t in TRAITS[k]:
            out.append(f'<span class="pill {cls}" title="{html.escape(t["hinweis"])}">{html.escape(t["saeule"][0])} &middot; {html.escape(t["wort"])}</span>')
        out.append('</div>')
    out.append('<p style="font-size:.85rem;color:var(--mute)">K = Kampf, S = Sozial, W = Wissen. Mit der Maus (oder lang gedrückt) siehst du den Hinweis.</p>')
    return ''.join(out)


def main():
    need = sorted({f['img'] for f in FIGS.values()})
    defs = []
    for n in need:
        p = next(os.path.join(IMG, n + e) for e in ('.png', '.jpg') if os.path.exists(os.path.join(IMG, n + e)))
        uri, (iw, ih) = jpeg_uri(p)
        defs.append(f'<image id="im-{n}" width="{iw}" height="{ih}" href="{uri}"/>')
    out = SRC.replace('{{IMGDEFS}}', '\n'.join(defs))
    out = re.sub(r'\{\{FIG:(\w+)\}\}', lambda m: fig(m.group(1)), out)
    out = out.replace('{{TRAITS}}', traits_html())
    out = out.replace('{{ORACLE_JSON}}', json.dumps(ORACLE, ensure_ascii=False))
    poster = os.path.join(HERE, 'video', 'out', 'poster.jpg')
    if os.path.exists(poster):
        pu, _ = jpeg_uri(poster, 70, 960)
    else:
        pu = ''
    out = out.replace('{{POSTER}}', pu).replace('{{VIDMIN}}', VIDMIN)
    open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8').write(out)
    print('index.html', round(len(out) / 1024), 'KB')


main()
