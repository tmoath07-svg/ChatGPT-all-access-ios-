from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path
import math, json

ROOT = Path("GTAConverter/Assets.xcassets")
S = 1024
BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
REG = "/System/Library/Fonts/Supplemental/Arial.ttf"

def font(size, bold=True):
    path = BOLD if bold else REG
    try: return ImageFont.truetype(path, size)
    except OSError: return ImageFont.load_default()

def base(top, bottom, glow):
    im = Image.new("RGB", (S,S))
    p = im.load()
    for y in range(S):
        t = y/(S-1)
        for x in range(S):
            g=max(0,1-math.sqrt(((x-760)/850)**2+((y-220)/680)**2))
            p[x,y]=tuple(int(top[i]*(1-t)+bottom[i]*t+glow[i]*g) for i in range(3))
    return im.convert("RGBA")

def draw_icon(name, title, top, bottom, accent, symbol="car", classic=False):
    im=base(top,bottom,accent)
    haze=Image.new("RGBA",(S,S),(0,0,0,0)); h=ImageDraw.Draw(haze)
    h.ellipse((560,70,1180,690),fill=(*accent,85))
    im=Image.alpha_composite(im,haze.filter(ImageFilter.GaussianBlur(95)))
    d=ImageDraw.Draw(im)
    if classic:
        road=Image.new("RGBA",(S,S),(0,0,0,0)); r=ImageDraw.Draw(road)
        r.polygon([(390,570),(635,570),(950,1024),(70,1024)],fill=(25,28,35,210))
        r.line([(512,620),(512,1000)],fill=(*accent,210),width=9)
        r.line([(415,700),(250,1024)],fill=(115,120,130,150),width=5)
        r.line([(610,700),(780,1024)],fill=(115,120,130,150),width=5)
        im=Image.alpha_composite(im,road.filter(ImageFilter.GaussianBlur(2))); d=ImageDraw.Draw(im)
        title_font=font(112); label="GTAV MODS"
    else:
        # framed technical badge and stylized vehicle/gear mark
        d.rounded_rectangle((160,150,864,850),radius=150,outline=(*accent,235),width=18)
        d.rounded_rectangle((185,175,839,825),radius=132,outline=(255,255,255,38),width=5)
        if symbol=="car":
            d.rounded_rectangle((300,430,724,635),radius=72,outline=(255,255,255,245),width=24)
            d.line((365,430,435,320,625,320,690,430),fill=(255,255,255,245),width=24)
            d.ellipse((350,590,470,710),fill=(*accent,255),outline=(255,255,255,255),width=13)
            d.ellipse((555,590,675,710),fill=(*accent,255),outline=(255,255,255,255),width=13)
        elif symbol=="bolt":
            d.polygon([(565,260),(350,555),(490,555),(420,760),(680,450),(535,450)],fill=(255,255,255,245))
        elif symbol=="stack":
            for off in (0,65,130):
                d.rounded_rectangle((290+off//3,315+off,735-off//3,465+off),radius=32,outline=(255,255,255,235),width=18)
        else:
            pts=[(512,250),(570,390),(725,410),(610,515),(645,680),(512,600),(379,680),(414,515),(299,410),(454,390)]
            d.polygon(pts,fill=(*accent,255),outline=(255,255,255,245))
        title_font=font(94); label="INRPF"
    box=d.textbbox((0,0),label,font=title_font,stroke_width=1)
    x=(S-(box[2]-box[0]))//2
    y=790 if not classic else 330
    d.text((x+4,y+7),label,font=title_font,fill=(0,0,0,220),stroke_width=2,stroke_fill=(0,0,0,220))
    d.text((x,y),label,font=title_font,fill=(255,255,255,255),stroke_width=1,stroke_fill=(255,255,255,150))
    if classic:
        f=font(54); tag="Moa_sa7"; bb=d.textbbox((0,0),tag,font=f); tw=bb[2]-bb[0]; tx=(S-tw)//2
        d.rounded_rectangle((tx-34,475,tx+tw+34,575),radius=24,fill=(8,10,15,220),outline=(*accent,230),width=3)
        d.text((tx,485),tag,font=f,fill=(*accent,255))
    folder=ROOT/(name+".appiconset"); folder.mkdir(parents=True,exist_ok=True)
    im.convert("RGB").save(folder/(name+".png"),"PNG",optimize=True)
    (folder/"Contents.json").write_text(json.dumps({"images":[{"filename":name+".png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}},indent=2)+"\n")
    print("Generated",name)

draw_icon("AppIcon","INRPF",(12,8,28),(5,5,13),(115,42,255),"car")
draw_icon("AppIcon-Classic","Classic",(9,11,17),(15,18,27),(155,18,28),"car",True)
draw_icon("AppIcon-Cyber","Cyber",(3,20,42),(2,6,18),(0,165,255),"bolt")
draw_icon("AppIcon-Carbon","Carbon",(45,49,57),(5,7,11),(130,145,165),"stack")
draw_icon("AppIcon-Gold","Gold",(35,23,5),(8,6,3),(235,170,45),"crown")
