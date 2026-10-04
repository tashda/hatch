# Hatch app icon: a doorway (arch) with a warm dot. Built from one symmetric centreline stroke with round caps.
CX=512; W=450; SW=104; TOP=225; BOTTOM=790          # outer width, stroke, outer top, outer bottom (incl. cap)
RC=(W-SW)/2                                         # centreline radius
YC=TOP+W/2                                          # arc centre y
YB=BOTTOM-SW/2                                      # centreline end (cap adds SW/2)
DOT_R=88; DOT_Y=596
ARCH=f"M{CX-RC} {YB} V{YC} A{RC} {RC} 0 0 1 {CX+RC} {YC} V{YB}"
svg=f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024"><defs>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#e8edf7"/></linearGradient>
<linearGradient id="ar" gradientUnits="userSpaceOnUse" x1="0" y1="{TOP}" x2="0" y2="{BOTTOM}"><stop offset="0" stop-color="#4180f0"/><stop offset="1" stop-color="#1f49aa"/></linearGradient>
<linearGradient id="dt" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffc65a"/><stop offset="1" stop-color="#ffa01c"/></linearGradient>
<filter id="tsh" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="14" stdDeviation="14" flood-color="#000" flood-opacity=".32"/></filter>
<clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="186"/></clipPath></defs>
<rect x="100" y="100" width="824" height="824" rx="186" fill="url(#bg)" filter="url(#tsh)"/>
<rect x="101" y="101" width="822" height="822" rx="185" fill="none" stroke="rgba(20,40,90,.16)" stroke-width="2"/>
<g clip-path="url(#tile)"><path d="{ARCH}" fill="none" stroke="url(#ar)" stroke-width="{SW}" stroke-linecap="round"/>
<circle cx="{CX}" cy="{DOT_Y}" r="{DOT_R}" fill="url(#dt)"/></g></svg>'''
open("hatch_icon.svg","w").write(svg)
