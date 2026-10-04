import math, random
def egg_path(cx=512,cy=545,a=212,b=272,k=0.17,n=120):
    return "M"+" L".join(f"{cx+a*math.cos(2*math.pi*i/n)*(1-k*math.sin(2*math.pi*i/n)):.1f} {cy-b*math.sin(2*math.pi*i/n):.1f}" for i in range(n))+" Z"
EGG=egg_path()
def jit(p,seed,amp=5,n=3):
    r=random.Random(seed); out=[p[0]]
    for (x0,y0),(x1,y1) in zip(p,p[1:]):
        for i in range(1,n+1):
            t=i/n
            out.append((round(x0+(x1-x0)*t+r.uniform(-amp,amp),1),round(y0+(y1-y0)*t+r.uniform(-amp,amp),1)) if i<n else (x1,y1))
    return out
def pl(p): return " ".join(f"{x},{y}" for x,y in p)
MAIN=jit(jit([(298,590),(346,566),(372,604),(424,574),(462,618),(512,584),(552,528),(598,556),(636,506),(668,526),(724,470)],1),11,2.5,3)
BR1=jit([(462,618),(446,664),(468,700),(452,744)],2)
BR2=jit([(552,528),(534,478),(556,436)],3)
BR3=jit([(372,604),(360,650),(338,676)],4)
def st(*a): return "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o,c in a)
BRN=st((0,"#e2ac7c"),(.5,"#bf7f4a"),(1,"#8a5028")); LIN=st((0,"#f6efe3"),(1,"#d9c8ac"))


import math
def taper(p,wmax,power=.8):
    n=len(p); L=[0]
    for a,b in zip(p,p[1:]): L.append(L[-1]+math.dist(a,b))
    T=L[-1]; left=[];right=[]
    for k,(x,y) in enumerate(p):
        a=p[max(k-1,0)];b=p[min(k+1,n-1)]
        dx,dy=b[0]-a[0],b[1]-a[1]; d=math.hypot(dx,dy) or 1; nx,ny=-dy/d,dx/d
        t=L[k]/T; w=wmax*(math.sin(math.pi*t)**power)/2*(1+0.28*math.sin(k*2.3)+0.18*math.sin(k*5.1+1))+.8
        left.append((x+nx*w,y+ny*w)); right.append((x-nx*w,y-ny*w))
    return "M"+" L".join(f"{x:.1f} {y:.1f}" for x,y in left+right[::-1])+" Z"
def icon(style, rimc='#f6dcb8', light="#ffcb5a", core="#fff6cf", deep="#ff9d2e", halo_op=0, w=1.0, branches=(1,1,1)):
    r=random.Random(7); sp=""
    for _ in range(80):
        while True:
            x=r.uniform(300,724);y=r.uniform(285,805)
            if ((x-512)/208)**2+((y-545)/268)**2<0.85: break
        sp+=f'<ellipse cx="{x:.0f}" cy="{y:.0f}" rx="{r.uniform(1.5,5.5):.1f}" ry="{r.uniform(1.2,3.5):.1f}" fill="#6b4020" opacity="{r.uniform(.15,.55):.2f}" transform="rotate({r.randint(0,180)} {x:.0f} {y:.0f})"/>'
    lines=[(MAIN,1.0)]+[(b,s) for b,s,on in ((BR1,.75,branches[0]),(BR2,.7,branches[1]),(BR3,.6,branches[2])) if on]
    def strokes(width,color,extra=""):
        return "".join(f'<polyline points="{pl(p)}" stroke="{color}" stroke-width="{width*s*w:.1f}" {extra}/>' for p,s in lines)
    crack=""
    if style=="candle":   # light seen through the shell, crack itself dark and thin
        crack=f'''<ellipse cx="520" cy="560" rx="190" ry="140" fill="url(#cand)" filter="url(#b16)"/>
<g fill="none" stroke-linecap="round" stroke-linejoin="round"><g filter="url(#b6)" opacity=".9">{strokes(14,light)}</g>{strokes(4.5,core)}</g>
<g fill="none" stroke-linecap="round" stroke-linejoin="round" opacity=".55">{strokes(2.2,"#2a1608","transform='translate(-1.5 -2)'")}</g>'''
    elif style=="tap":
        wm=w; P=taper(MAIN,wm)
        P2=taper(MAIN,wm+10)
        crack=(f'''<ellipse cx="520" cy="560" rx="190" ry="140" fill="url(#cand)" filter="url(#b16)" opacity="{halo_op}"/>
<path d="{P2}" fill="{rimc}" opacity=".9"/>
<path d="{P}" fill="{core}"/>
<path d="{P}" fill="url(#ins)"/>
<path d="{taper(MAIN,wm*.35)}" fill="{light}" opacity=".9"/>
<g opacity=".9"><path d="{taper(BR1,7,.6)}" fill="#3a2010"/><path d="{taper(BR1,3,.6)}" fill="#fff1d2" opacity=".8"/></g>''')
    elif style=="thin":   # soft, thin warm light only inside the crack, no outer glow
        crack=f'''<g fill="none" stroke-linecap="round" stroke-linejoin="round"><g filter="url(#b3)" opacity=".8">{strokes(9,light)}</g>{strokes(3.6,core)}</g>
<g fill="none" stroke-linecap="round" stroke-linejoin="round" opacity=".6">{strokes(2,"#2a1608","transform='translate(-1.4 -2)'")}</g>'''
    elif style=="gap":    # real gap: dark crack with light edge and warm light deep inside
        crack=f'''<g fill="none" stroke-linecap="round" stroke-linejoin="round">{strokes(11,"#fff3dc","opacity='.75'")}{strokes(8,"#2a1608")}<g filter="url(#b3)">{strokes(4.2,light)}</g>{strokes(2,core)}</g>'''
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">{LIN}</linearGradient>
<radialGradient id="shell" cx="36%" cy="26%" r="95%">{BRN}</radialGradient>
<radialGradient id="halo" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="{deep}" stop-opacity="{halo_op}"/><stop offset=".5" stop-color="{deep}" stop-opacity="{halo_op*.3}"/><stop offset="1" stop-color="{deep}" stop-opacity="0"/></radialGradient>
<radialGradient id="cand" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="{light}" stop-opacity=".95"/><stop offset=".55" stop-color="{deep}" stop-opacity=".45"/><stop offset="1" stop-color="{deep}" stop-opacity="0"/></radialGradient>
<linearGradient id="ao" x1="0" y1="0" x2="0" y2="1"><stop offset=".45" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".38"/></linearGradient>
<radialGradient id="bounce" cx="70%" cy="95%" r="55%"><stop offset="0" stop-color="#fff" stop-opacity=".28"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
<radialGradient id="side" cx="30%" cy="35%" r="85%"><stop offset=".55" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".30"/></radialGradient>
<clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="186"/></clipPath>
<clipPath id="egg"><path d="{EGG}"/></clipPath>
<filter id="tsh" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="14" stdDeviation="14" flood-color="#000" flood-opacity=".35"/></filter>
<filter id="esh" filterUnits="userSpaceOnUse" x="150" y="700" width="760" height="250"><feGaussianBlur stdDeviation="22"/></filter>
<linearGradient id="ins" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity=".45"/><stop offset=".5" stop-color="#000" stop-opacity="0"/></linearGradient>
<filter id="b3"><feGaussianBlur stdDeviation="3"/></filter><filter id="b6"><feGaussianBlur stdDeviation="6"/></filter><filter id="b16"><feGaussianBlur stdDeviation="16"/></filter>
<filter id="grain" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="3"/><feColorMatrix values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 .55 -.18"/></filter>
</defs>
<rect x="100" y="100" width="824" height="824" rx="186" fill="url(#bg)" filter="url(#tsh)"/>
<g clip-path="url(#tile)">
<ellipse cx="512" cy="540" rx="400" ry="360" fill="url(#halo)"/>
<ellipse cx="512" cy="812" rx="200" ry="24" fill="#000" opacity=".45" filter="url(#esh)"/>
<g clip-path="url(#egg)">
 <path d="{EGG}" fill="url(#shell)"/><path d="{EGG}" fill="url(#ao)"/><path d="{EGG}" fill="url(#side)"/><path d="{EGG}" fill="url(#bounce)"/>
 <rect x="250" y="250" width="540" height="600" filter="url(#grain)" opacity=".5"/>{sp}
 <ellipse cx="420" cy="380" rx="62" ry="108" fill="#fff" opacity=".5" filter="url(#b16)" transform="rotate(22 420 380)"/>
 <ellipse cx="410" cy="362" rx="22" ry="52" fill="#fff" opacity=".7" filter="url(#b6)" transform="rotate(22 410 362)"/>
 {crack}
</g></g></svg>'''
V={"hatch":icon("tap",w=26,halo_op=0,light="#fff7e4",core="#fff1d2")}
for k,v in V.items(): open(k+".svg","w").write(v)
