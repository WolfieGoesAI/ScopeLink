import math, sys
from PIL import Image, ImageDraw, ImageFilter
S=1024
img=Image.new('RGBA',(S,S),(0,0,0,0))
d=ImageDraw.Draw(img)
# body (macOS-style rounded square with margin)
m=100
d.rounded_rectangle([m,m,S-m,S-m],radius=185,fill=(38,44,56,255))
d.rounded_rectangle([m+18,m+18,S-m-18,S-m-18],radius=170,outline=(70,80,98,255),width=6)
# screen
sx0,sy0,sx1,sy1=200,215,824,690
d.rounded_rectangle([sx0,sy0,sx1,sy1],radius=34,fill=(8,22,26,255))
# grid
for i in range(1,10):
    x=sx0+(sx1-sx0)*i/10; d.line([x,sy0+14,x,sy1-14],fill=(30,70,70,255),width=3)
for i in range(1,8):
    y=sy0+(sy1-sy0)*i/8; d.line([sx0+14,y,sx1-14,y],fill=(30,70,70,255),width=3)
# trace with glow
tr=Image.new('RGBA',(S,S),(0,0,0,0)); td=ImageDraw.Draw(tr)
pts=[]
for i in range(0,601):
    x=sx0+20+(sx1-sx0-40)*i/600
    t=i/600*2*math.pi*2
    y=(sy0+sy1)/2-150*math.sin(t)
    pts.append((x,y))
for i in range(len(pts)-1):
    (x0,y0),(x1,y1)=pts[i],pts[i+1]
    for k in range(8):
        x=x0+(x1-x0)*k/8; y=y0+(y1-y0)*k/8
        td.ellipse([x-11,y-11,x+11,y+11],fill=(255,214,40,255))
glow=tr.filter(ImageFilter.GaussianBlur(18))
img=Image.alpha_composite(img,glow); img=Image.alpha_composite(img,tr)
d=ImageDraw.Draw(img)
# USB plug at the bottom + knobs
for i,c in enumerate([(230,80,70),(70,170,240),(120,200,110)]):
    cx=300+i*160; d.ellipse([cx-42,775-42,cx+42,775+42],fill=c+(255,))
d.rounded_rectangle([700,745,820,805],radius=14,fill=(200,205,215,255))
d.rectangle([724,762,744,788],fill=(38,44,56,255)); d.rectangle([776,762,796,788],fill=(38,44,56,255))
img.save(sys.argv[1])
