"""Render native Yoga layout/style traces for offline review.

These are diagnostic reconstructions, not GPU screenshots: font rasterization,
button fitting, hover effects and the arena are not reproduced by this tool.
"""
import json
import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

FONT = 'C:/Windows/Fonts/msyh.ttc'

def rgba(value, default=(0, 0, 0, 0)):
    if not isinstance(value, list):
        return default
    return tuple(round(v) for v in (value + [255])[:4])

def render(path):
    data = json.loads(path.read_text(encoding='utf-8'))
    w, h = math.ceil(data['w']), math.ceil(data['h'])
    canvas = Image.new('RGBA', (w, h), (10, 15, 19, 255))
    for item in data['widgets']:
        if item['w'] < .1 or item['h'] < .1:
            continue
        layer = Image.new('RGBA', (w, h))
        draw = ImageDraw.Draw(layer)
        x, y, bw, bh = (item[k] for k in ('x', 'y', 'w', 'h'))
        box = (round(x), round(y), round(x+bw), round(y+bh))
        bg = rgba(item.get('bg'))
        if item.get('button') and item.get('disabled'):
            bg = (10, 15, 19, 255)
        if bg[3]:
            draw.rectangle(box, fill=bg)
        border = rgba(item.get('border'))
        width = item.get('borderWidth') or 0
        if isinstance(width, (int, float)) and width > 0:
            draw.rectangle(box, outline=border, width=max(1, round(width)))
        value = item.get('text', '')
        if value:
            size = round(item.get('fontSize') or 14)
            font = ImageFont.truetype(FONT, max(8, size))
            if item.get('button'):
                while font.getlength(value) > bw-10 and size > 9:
                    size -= 1
                    font = ImageFont.truetype(FONT, size)
                lines = [value]
            else:
                lines = []
                for paragraph in value.split('\n'):
                    line = ''
                    for char in paragraph:
                        if line and font.getlength(line+char) > max(1, bw):
                            lines.append(line)
                            line = char
                        else:
                            line += char
                    lines.append(line)
            line_height = size*1.3
            ty = y + (max(0, bh-line_height*len(lines))/2 if item.get('button') else 0)
            c = rgba(item.get('color'), (236, 230, 210, 255))
            if item.get('disabled'):
                c = (156, 165, 160, 255)
            for line in lines:
                align = 'center' if item.get('button') else item.get('align')
                tx = x + ((bw-font.getlength(line))/2 if align == 'center' else max(0, bw-font.getlength(line)) if align == 'right' else 0)
                draw.text((tx, ty), line, fill=c, font=font)
                ty += line_height
        clip = item.get('clip')
        if clip:
            left, top = max(0, round(clip['x'])), max(0, round(clip['y']))
            right, bottom = min(w, round(clip['x']+clip['w'])), min(h, round(clip['y']+clip['h']))
            if right > left and bottom > top:
                canvas.alpha_composite(layer.crop((left, top, right, bottom)), (left, top))
        else:
            canvas.alpha_composite(layer)
    # Label each artifact honestly; never confuse the reconstruction with a capture.
    ImageDraw.Draw(canvas).text((6, h-17), 'NATIVE LAYOUT TRACE / NOT A GAME SCREENSHOT',
        font=ImageFont.truetype(FONT, 9), fill=(100, 116, 123, 255))
    output = path.with_name(path.stem.replace('-layout', '')+'-trace.png')
    canvas.convert('RGB').save(output)
    return output

if __name__ == '__main__':
    for source in Path(sys.argv[1]).glob('*-layout.json'):
        print(render(source))
