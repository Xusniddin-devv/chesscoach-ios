import subprocess, os
S=os.getcwd()
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
def laurel(top,bottom):
    l="<svg viewBox=\"-20 -10 120 210\" width=\"92\" height=\"160\"><path d=\"M70 190 Q4 110 52 10\" stroke=\"#FF6A1A\" stroke-width=\"4\" fill=\"none\" stroke-linecap=\"round\"/><ellipse cx=\"43.3\" cy=\"170.3\" rx=\"16\" ry=\"7\" fill=\"#FF6A1A\" transform=\"rotate(-166.6 43.3 170.3)\"/><ellipse cx=\"60.4\" cy=\"159.0\" rx=\"16\" ry=\"7\" fill=\"#FF6A1A\" transform=\"rotate(-80.7 60.4 159.0)\"/><ellipse cx=\"30.9\" cy=\"144.4\" rx=\"16\" ry=\"7\" fill=\"#FF6A1A\" transform=\"rotate(-157.4 30.9 144.4)\"/><ellipse cx=\"49.5\" cy=\"135.9\" rx=\"16\" ry=\"7\" fill=\"#FF6A1A\" transform=\"rotate(-71.4 49.5 135.9)\"/><ellipse cx=\"23.5\" cy=\"117.6\" rx=\"16\" ry=\"7\" fill=\"#FF6A1A\" transform=\"rotate(-147.2 23.5 117.6)\"/><ellipse cx=\"43.4\" cy=\"112.6\" rx=\"16\" ry=\"7\" fill=\"#FF6A1A\" transform=\"rotate(-61.3 43.4 112.6)\"/><ellipse cx=\"21.2\" cy=\"90.2\" rx=\"16\" ry=\"7\" fill=\"#FF6A1A\" transform=\"rotate(-136.9 21.2 90.2)\"/><ellipse cx=\"41.6\" cy=\"88.8\" rx=\"16\" ry=\"7\" fill=\"#FF6A1A\" transform=\"rotate(-50.9 41.6 88.8)\"/><ellipse cx=\"23.7\" cy=\"62.4\" rx=\"16\" ry=\"7\" fill=\"#FF6A1A\" transform=\"rotate(-126.9 23.7 62.4)\"/><ellipse cx=\"44.0\" cy=\"64.6\" rx=\"16\" ry=\"7\" fill=\"#FF6A1A\" transform=\"rotate(-40.9 44.0 64.6)\"/><ellipse cx=\"30.8\" cy=\"34.3\" rx=\"16\" ry=\"7\" fill=\"#FF6A1A\" transform=\"rotate(-117.8 30.8 34.3)\"/><ellipse cx=\"50.5\" cy=\"39.7\" rx=\"16\" ry=\"7\" fill=\"#FF6A1A\" transform=\"rotate(-31.8 50.5 39.7)\"/><ellipse cx=\"42.4\" cy=\"5.8\" rx=\"16\" ry=\"7\" fill=\"#FF6A1A\" transform=\"rotate(-109.8 42.4 5.8)\"/><ellipse cx=\"61.2\" cy=\"13.9\" rx=\"16\" ry=\"7\" fill=\"#FF6A1A\" transform=\"rotate(-23.9 61.2 13.9)\"/></svg>"
    return f'''<div class="laurel"><div class="lf">{l}</div><div class="lt"><b>{top}</b><span>{bottom}</span></div><div class="lf r">{l}</div></div>'''
HEAD='<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="tilt.css"><style>%s</style></head><body>'
def render(name, body, css=""):
    open(f"{name}.html","w").write(HEAD%css+body+"</body></html>")
    subprocess.run([CH,"--headless=new","--disable-gpu","--hide-scrollbars","--force-device-scale-factor=1","--window-size=1320,2868",f"--screenshot={S}/{name}.png",f"file://{S}/{name}.html"],capture_output=True)

banner_css='''
.hero{position:absolute;inset:0;background:url(bg/hero0.png) 46% 100%/auto 104% no-repeat #0b0d10}
.shade{position:absolute;inset:0;background:linear-gradient(#090b0e 0%,rgba(9,11,14,.85) 22%,rgba(9,11,14,0) 45%,rgba(9,11,14,0) 78%,rgba(9,11,14,.92) 100%)}
.top{position:absolute;top:190px;left:0;right:0;text-align:center}
.app{display:inline-flex;align-items:center;gap:26px;margin-bottom:56px}
.app img{width:120px;height:120px;border-radius:27px;box-shadow:0 10px 40px rgba(0,0,0,.6)}
.app span{font-size:54px;font-weight:700}
.top h1{font-size:136px;letter-spacing:-4px}
.top p{font-size:54px;color:rgba(236,238,238,.72);margin-top:34px;font-weight:500}
.laurels{position:absolute;bottom:150px;left:0;right:0;display:flex;justify-content:center;gap:70px}
.laurel{display:flex;align-items:center;gap:6px}
.lf.r{transform:scaleX(-1)}
.lt{text-align:center;display:flex;flex-direction:column;min-width:300px}
.lt b{font-size:52px;font-weight:800}
.lt span{font-size:32px;color:rgba(236,238,238,.7);margin-top:6px;font-weight:600;letter-spacing:1px;text-transform:uppercase}
'''
render("s1",f'''<div class="hero"></div><div class="shade"></div>
<div class="top"><div class="app"><img src="icon.png"><span>Chess Coach</span></div>
<h1>Your own<br><em>chess coach</em></h1><p>It learns from the games you play.</p></div>
<div class="laurels">{laurel("Stockfish 18","On your iPhone")}{laurel("No ads","No tracking")}</div>''',banner_css)

def tilt(name, eyebrow, h1, shot, mascot, bubble, chips="", flip=False, rot="rotateY(-16deg) rotateX(8deg) rotateZ(-7deg)", px=330, py=860, mx=-30, my=2180, ms=640, bx=70, by=1930, side="tl"):
    render(name,f'''<div class="bg{' flip' if flip else ''}"></div><div class="grid"></div>
<div class="cap"><div class="eyebrow">{eyebrow}</div><h1>{h1}</h1></div>
<div class="stage"><div class="phone" style="left:{px}px;top:{py}px;transform:{rot}"><img src="{shot}"></div></div>
{chips}
<img class="mascot" src="coach-{mascot}@3x.png" style="left:{mx}px;top:{my}px;width:{ms}px">
<div class="bubble {side}" style="left:{bx}px;top:{by}px">{bubble}</div>''')

def chip(x,y,color,glyph,text): return f'<div class="chip" style="left:{x}px;top:{y}px"><div class="dot" style="background:{color}">{glyph}</div>{text}</div>'

tilt("s2","Training mode","A coach that<br><em>explains</em> every<br>mistake","merged-coach.png","concerned","Hmm. That bishop<br>can be taken.",
     chip(700,1500,"#FF3B46","??","Blunder caught"))
tilt("s3","Game review","Every move,<br><em>graded</em>","merged-review.png","thinking","Here’s where<br>it turned.",
     chip(80,1060,"#26C2A3","!!","Brilliant")+chip(760,1260,"#FF3B46","??","Blunder"),flip=True,rot="rotateY(16deg) rotateX(8deg) rotateZ(7deg)",px=120,mx=710,my=2180,bx=600,by=1930,side="tr")
tilt("s4","Puzzles","Your mistakes<br>become <em>puzzles</em>","merged-puzzle-solver.png","neutral","You missed this<br>fork. Try again!",
     chip(640,1180,"#FF6A1A","♞","From your own games"))
tilt("s5","Daily plan","A plan for<br><em>each day</em>","final-home.png","pleased","Ten minutes<br>a day. Let’s go!",
     chip(90,1150,"#FF6A1A","1","day streak"),flip=True,rot="rotateY(16deg) rotateX(8deg) rotateZ(7deg)",px=120,mx=710,my=2180,bx=600,by=1930,side="tr")
tilt("s6","Play bots","Bots rated<br><em>600 to 2300</em>","plan4-deslop-botladder-new.png","neutral","Start with Pip.<br>Work up to Vera.")
tilt("s7","Your profile","See what costs<br>you <em>points</em>","final-onb-reveal.png","thinking","You leave pieces<br>undefended.",
     flip=True,rot="rotateY(16deg) rotateX(8deg) rotateZ(7deg)",px=120,mx=710,my=2180,bx=600,by=1930,side="tr")
