# dividers.py shot.png -> list-header column dividers (window points), left to right
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('L')
W = im.size[0]
Y = int(sys.argv[2]) if len(sys.argv) > 2 else 214
def bg(x, y): return abs(im.getpixel((x, y)) - im.getpixel((x - 6, y))) < 6
res = []
for x in range(500, W - 30):
    # a divider is a thin vertical line through the header text band (y 200–228 px)
    if all(im.getpixel((x, y)) > im.getpixel((x - 3, y)) + 10 for y in range(Y - 12, Y + 12, 3)):
        if not res or x - res[-1] > 3: res.append(x)
print(" ".join(f"{x / 2:.1f}" for x in res))
