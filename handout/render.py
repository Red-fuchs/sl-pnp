import sys, pymupdf
from PIL import Image
d = pymupdf.open(sys.argv[1]); out = sys.argv[2]; n = len(d); print(n, 'pages')
ims = []
for i, p in enumerate(d):
    p.get_pixmap(dpi=75).save(f'{out}/p{i+1:02d}.png'); ims.append(Image.open(f'{out}/p{i+1:02d}.png'))
w, h = ims[0].size
for k in range(0, n, 3):
    sh = Image.new('RGB', (w * 3, h), 'white')
    for j, im in enumerate(ims[k:k+3]): sh.paste(im, (j * w, 0))
    sh.save(f'{out}/s{k//3+1}.png')
