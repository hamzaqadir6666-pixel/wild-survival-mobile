#!/usr/bin/env python3
"""Draws the white UI icons (assets/ui/*.png, 96 px). Tinted in the game with modulate."""
import math, os
from PIL import Image, ImageDraw
S = 96; K = 4; N = S * K
OUT = 'assets/ui'; os.makedirs(OUT, exist_ok=True)
W = (255, 255, 255, 255)
def new(): 
    im = Image.new('RGBA', (N, N), (255, 255, 255, 0)); return im, ImageDraw.Draw(im)
def P(*pts): return [(x * N, y * N) for x, y in pts]
def circ(d, x, y, r, fill=W): d.ellipse([(x - r) * N, (y - r) * N, (x + r) * N, (y + r) * N], fill=fill)
def ring(d, x, y, r, w): d.ellipse([(x - r) * N, (y - r) * N, (x + r) * N, (y + r) * N], outline=W, width=int(w * N))
def line(d, pts, w): d.line(P(*pts), fill=W, width=int(w * N), joint='curve')
def save(im, name): im.resize((S, S), Image.LANCZOS).save(f'{OUT}/{name}.png')
C = (255, 255, 255, 0)
icons = {}
def icon(f): icons[f.__name__] = f; return f
@icon
def heart(d):
    circ(d, .32, .36, .2); circ(d, .68, .36, .2); d.polygon(P((.13, .44), (.87, .44), (.5, .88)), fill=W)
@icon
def bolt(d): d.polygon(P((.58, .08), (.22, .56), (.46, .56), (.38, .92), (.78, .42), (.54, .42)), fill=W)
@icon
def leaf(d):
    d.pieslice([.1 * N, .1 * N, .9 * N, .9 * N], 180, 270, fill=W); d.pieslice([.1 * N, .1 * N, .9 * N, .9 * N], 0, 90, fill=W)
    d.polygon(P((.5, .1), (.9, .5), (.5, .9), (.1, .5)), fill=W); line(d, [(.16, .86), (.5, .52)], .05)
    d.line(P((.3, .7), (.72, .28)), fill=C, width=int(.035 * N))
@icon
def drop(d): circ(d, .5, .62, .27); d.polygon(P((.5, .08), (.75, .52), (.25, .52)), fill=W)
@icon
def paw(d):
    d.ellipse([.28 * N, .46 * N, .72 * N, .86 * N], fill=W)
    for x, y in ((.2, .42), (.38, .24), (.62, .24), (.8, .42)): d.ellipse([(x - .09) * N, (y - .12) * N, (x + .09) * N, (y + .12) * N], fill=W)
@icon
def flag(d): line(d, [(.26, .1), (.26, .92)], .07); d.polygon(P((.3, .12), (.82, .3), (.3, .5)), fill=W)
@icon
def eye(d):
    d.polygon(P((.06, .5), (.3, .28), (.5, .22), (.7, .28), (.94, .5), (.7, .72), (.5, .78), (.3, .72)), fill=W); circ(d, .5, .5, .15, C); circ(d, .5, .5, .07)
@icon
def clock(d): ring(d, .5, .5, .4, .08); line(d, [(.5, .26), (.5, .5), (.68, .6)], .07)
@icon
def map(d):
    d.polygon(P((.1, .22), (.36, .12), (.64, .22), (.9, .12), (.9, .78), (.64, .88), (.36, .78), (.1, .88)), fill=W)
    d.line(P((.36, .14), (.36, .78)), fill=C, width=int(.04 * N)); d.line(P((.64, .22), (.64, .86)), fill=C, width=int(.04 * N))
@icon
def pause(d): d.rounded_rectangle([.24 * N, .18 * N, .42 * N, .82 * N], .04 * N, fill=W); d.rounded_rectangle([.58 * N, .18 * N, .76 * N, .82 * N], .04 * N, fill=W)
@icon
def play(d): d.polygon(P((.26, .14), (.84, .5), (.26, .86)), fill=W)
@icon
def jump(d): d.polygon(P((.5, .1), (.86, .48), (.62, .48), (.62, .68), (.38, .68), (.38, .48), (.14, .48)), fill=W); d.rounded_rectangle([.22 * N, .78 * N, .78 * N, .88 * N], .03 * N, fill=W)
@icon
def sprint(d):
    for o in (0, .3): d.polygon(P((.12 + o, .16), (.3 + o, .16), (.58 + o, .5), (.3 + o, .84), (.12 + o, .84), (.4 + o, .5)), fill=W)
@icon
def sneak(d):
    for x, y in ((.34, .66), (.66, .36)):
        d.ellipse([(x - .12) * N, (y - .2) * N, (x + .12) * N, (y + .14) * N], fill=W); circ(d, x, y + .24, .08)
@icon
def clover(d):
    for a in (90, 210, 330): circ(d, .5 + .2 * math.cos(math.radians(a)), .42 - .2 * math.sin(math.radians(a)), .19)
    line(d, [(.5, .5), (.56, .92)], .06)
@icon
def moon(d): circ(d, .48, .5, .38); circ(d, .66, .4, .32, C)
@icon
def shield(d): d.polygon(P((.5, .08), (.86, .22), (.82, .6), (.5, .92), (.18, .6), (.14, .22)), fill=W)
@icon
def sun(d):
    circ(d, .5, .5, .22)
    for i in range(8):
        a = i * math.pi / 4; line(d, [(.5 + .3 * math.cos(a), .5 + .3 * math.sin(a)), (.5 + .44 * math.cos(a), .5 + .44 * math.sin(a))], .07)
@icon
def ghost(d):
    d.pieslice([.18 * N, .1 * N, .82 * N, .74 * N], 180, 360, fill=W); d.rectangle([.18 * N, .42 * N, .82 * N, .8 * N], fill=W)
    for x in (.26, .5, .74): circ(d, x, .8, .09)
    circ(d, .38, .42, .07, C); circ(d, .62, .42, .07, C)
@icon
def wave(d):
    for y in (.34, .58, .82):
        line(d, [(.08 + i * .042, y + .07 * math.sin(i * .9)) for i in range(21)], .07)
@icon
def cross(d): d.rounded_rectangle([.38 * N, .12 * N, .62 * N, .88 * N], .04 * N, fill=W); d.rounded_rectangle([.12 * N, .38 * N, .88 * N, .62 * N], .04 * N, fill=W)
@icon
def honey(d): d.polygon(P(*[(.5 + .4 * math.cos(math.radians(60 * i)), .5 + .4 * math.sin(math.radians(60 * i))) for i in range(6)]), fill=W); circ(d, .5, .5, .14, C)
@icon
def skull(d):
    circ(d, .5, .42, .32); d.rounded_rectangle([.32 * N, .6 * N, .68 * N, .86 * N], .05 * N, fill=W)
    circ(d, .38, .42, .09, C); circ(d, .62, .42, .09, C)
    for x in (.44, .56): d.line(P((x, .72), (x, .86)), fill=C, width=int(.03 * N))
@icon
def lock(d): ring(d, .5, .36, .2, .08); d.rounded_rectangle([.2 * N, .42 * N, .8 * N, .88 * N], .06 * N, fill=W)
@icon
def star(d): d.polygon(P(*[(.5 + (.44 if i % 2 == 0 else .19) * math.sin(math.radians(36 * i)), .52 - (.44 if i % 2 == 0 else .19) * math.cos(math.radians(36 * i))) for i in range(10)]), fill=W)
@icon
def cloud(d):
    circ(d, .34, .56, .2); circ(d, .54, .42, .24); circ(d, .72, .58, .18); d.rectangle([.34 * N, .56 * N, .72 * N, .76 * N], fill=W)
@icon
def rain(d):
    circ(d, .34, .4, .18); circ(d, .54, .3, .22); circ(d, .72, .42, .16); d.rectangle([.34 * N, .4 * N, .72 * N, .58 * N], fill=W)
    for x in (.3, .5, .7): line(d, [(x, .68), (x - .06, .9)], .06)
@icon
def storm(d):
    circ(d, .34, .36, .18); circ(d, .54, .26, .22); circ(d, .72, .38, .16); d.rectangle([.34 * N, .36 * N, .72 * N, .54 * N], fill=W)
    d.polygon(P((.56, .56), (.36, .78), (.5, .78), (.42, .96), (.68, .7), (.54, .7)), fill=W)
@icon
def arrow(d): d.polygon(P((.5, .06), (.84, .9), (.5, .7), (.16, .9)), fill=W)
@icon
def mushroom(d):
    d.pieslice([.1 * N, .14 * N, .9 * N, .9 * N], 180, 360, fill=W); d.rounded_rectangle([.4 * N, .5 * N, .6 * N, .9 * N], .05 * N, fill=W); circ(d, .5, .34, .08, C)
@icon
def back(d): d.polygon(P((.1, .5), (.5, .14), (.5, .38), (.9, .38), (.9, .62), (.5, .62), (.5, .86)), fill=W)
@icon
def gear(d):
    for i in range(8):
        a = i * math.pi / 4; line(d, [(.5 + .25 * math.cos(a), .5 + .25 * math.sin(a)), (.5 + .43 * math.cos(a), .5 + .43 * math.sin(a))], .13)
    circ(d, .5, .5, .31); circ(d, .5, .5, .13, C)
for name, f in icons.items():
    im, d = new(); f(d); save(im, name)
print(len(icons), 'icons')
