#!/usr/bin/env python3
"""Generate Squad Brunch app icon: Bloody Mary + Mimosa clinking."""

import subprocess
import shutil
import os


def build_svg():
    return """\
<?xml version="1.0" encoding="UTF-8"?>
<svg width="1024" height="1024" viewBox="0 0 1024 1024"
     xmlns="http://www.w3.org/2000/svg">
  <defs>
    <radialGradient id="bgGlow" cx="50%" cy="86%" r="58%">
      <stop offset="0%" stop-color="#FF6B47" stop-opacity="0.22"/>
      <stop offset="100%" stop-color="#FF6B47" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="ojGrad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%"   stop-color="#FFE880"/>
      <stop offset="55%"  stop-color="#FFB020"/>
      <stop offset="100%" stop-color="#E87800"/>
    </linearGradient>
    <linearGradient id="bmGrad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%"   stop-color="#D84020"/>
      <stop offset="100%" stop-color="#6A0E08"/>
    </linearGradient>
    <linearGradient id="celGrad" x1="0" y1="1" x2="0" y2="0">
      <stop offset="0%"   stop-color="#3A7A28"/>
      <stop offset="100%" stop-color="#66CC44"/>
    </linearGradient>

    <filter id="clinkGlow" x="-80%" y="-80%" width="260%" height="260%">
      <feGaussianBlur stdDeviation="14" result="blur"/>
      <feMerge>
        <feMergeNode in="blur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
    <filter id="iceGlow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="3" result="blur"/>
      <feMerge>
        <feMergeNode in="blur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>

  <!-- ── Background ── -->
  <rect width="1024" height="1024" fill="#0F0F14"/>
  <rect width="1024" height="1024" fill="url(#bgGlow)"/>

  <!-- ══════════════════════════════════════════
       LEFT GLASS — MIMOSA FLUTE
       Base center (320, 880), rotate +12°
       ══════════════════════════════════════════ -->
  <g transform="translate(320,880) rotate(12)">

    <!-- Base plate -->
    <rect x="-46" y="-15" width="92" height="15" rx="7.5"
          fill="rgba(255,255,255,0.65)"/>

    <!-- Stem -->
    <rect x="-5.5" y="-148" width="11" height="133" rx="5.5"
          fill="rgba(255,255,255,0.55)"/>

    <!-- Bowl: liquid fill -->
    <path d="M -16 -148  L -54 -655  L 54 -655  L 16 -148  Z"
          fill="url(#ojGrad)" fill-opacity="0.92"/>

    <!-- Bowl: glass outline -->
    <path d="M -16 -148  L -54 -655  L 54 -655  L 16 -148  Z"
          fill="none" stroke="rgba(255,255,255,0.62)" stroke-width="5.5"
          stroke-linejoin="round"/>

    <!-- Foam cap -->
    <ellipse cx="0"   cy="-655" rx="52"  ry="21"  fill="white" fill-opacity="0.92"/>
    <ellipse cx="-16" cy="-663" rx="23"  ry="14"  fill="white" fill-opacity="0.78"/>
    <ellipse cx="17"  cy="-661" rx="19"  ry="12"  fill="white" fill-opacity="0.72"/>

    <!-- Bubbles -->
    <circle cx="-5"  cy="-225" r="5.5" fill="rgba(255,255,255,0.55)"/>
    <circle cx="10"  cy="-355" r="4.5" fill="rgba(255,255,255,0.48)"/>
    <circle cx="-9"  cy="-475" r="4"   fill="rgba(255,255,255,0.42)"/>
    <circle cx="5"   cy="-570" r="3.5" fill="rgba(255,255,255,0.38)"/>
    <circle cx="-3"  cy="-305" r="3"   fill="rgba(255,255,255,0.42)"/>
    <circle cx="12"  cy="-425" r="3.5" fill="rgba(255,255,255,0.38)"/>

    <!-- Left inner highlight -->
    <path d="M -44 -628  C -42 -455  -13 -178  -13 -152"
          stroke="rgba(255,255,255,0.28)" stroke-width="4.5"
          fill="none" stroke-linecap="round"/>

    <!-- Orange slice (right rim) -->
    <g transform="translate(52,-655) rotate(-18)">
      <!-- Peel -->
      <path d="M 0 0  L 0 -60  A 60 60 0 0 1 52 -30  Z"
            fill="#FF8C00" stroke="#C86000" stroke-width="1.5"/>
      <!-- Flesh -->
      <path d="M 0 -7  L 0 -52  A 52 52 0 0 1 45 -26  Z"
            fill="#FFB830" fill-opacity="0.85"/>
      <!-- Segment spokes -->
      <line x1="0" y1="-7"  x2="0"   y2="-52"  stroke="#C86000" stroke-width="1.2" stroke-opacity="0.5"/>
      <line x1="0" y1="-7"  x2="22.5" y2="-45" stroke="#C86000" stroke-width="1.2" stroke-opacity="0.5"/>
      <line x1="0" y1="-7"  x2="39"   y2="-22.5" stroke="#C86000" stroke-width="1.2" stroke-opacity="0.5"/>
      <!-- White pith -->
      <path d="M 0 -52  A 52 52 0 0 1 45 -26"
            stroke="rgba(255,255,255,0.80)" stroke-width="7"
            fill="none" stroke-linecap="round"/>
    </g>

  </g><!-- end mimosa -->


  <!-- ══════════════════════════════════════════
       RIGHT GLASS — BLOODY MARY HIGHBALL
       Base center (700, 880), rotate -12°
       ══════════════════════════════════════════ -->
  <g transform="translate(700,880) rotate(-12)">

    <!-- Base plate -->
    <rect x="-50" y="-15" width="100" height="15" rx="7.5"
          fill="rgba(255,255,255,0.65)"/>

    <!-- Glass body: liquid fill (highball, slight outward taper) -->
    <path d="M -47 -15  L -60 -655  L 60 -655  L 47 -15  Z"
          fill="url(#bmGrad)" fill-opacity="0.94"/>

    <!-- Glass body: outline -->
    <path d="M -47 -15  L -60 -655  L 60 -655  L 47 -15  Z"
          fill="none" stroke="rgba(255,255,255,0.62)" stroke-width="5.5"
          stroke-linejoin="round"/>

    <!-- Ice cubes (lower half) -->
    <g filter="url(#iceGlow)">
      <rect x="-40" y="-310" width="56" height="56" rx="11"
            fill="rgba(210,240,255,0.18)" stroke="rgba(255,255,255,0.42)" stroke-width="2.2"/>
      <rect x="-8"  y="-268" width="52" height="52" rx="11"
            fill="rgba(210,240,255,0.14)" stroke="rgba(255,255,255,0.37)" stroke-width="2.2"/>
      <rect x="-42" y="-220" width="48" height="48" rx="11"
            fill="rgba(210,240,255,0.11)" stroke="rgba(255,255,255,0.32)" stroke-width="2.2"/>
    </g>

    <!-- Right inner highlight -->
    <path d="M 50 -630  L 44 -55"
          stroke="rgba(255,255,255,0.22)" stroke-width="4.5"
          fill="none" stroke-linecap="round"/>

    <!-- Salt rim dots -->
    <circle cx="-50" cy="-655" r="5.5"  fill="rgba(255,255,255,0.88)"/>
    <circle cx="-32" cy="-659" r="5"    fill="rgba(255,255,255,0.82)"/>
    <circle cx="-13" cy="-661" r="5.5"  fill="rgba(255,255,255,0.88)"/>
    <circle cx="6"   cy="-661" r="5"    fill="rgba(255,255,255,0.82)"/>
    <circle cx="25"  cy="-659" r="5.5"  fill="rgba(255,255,255,0.88)"/>
    <circle cx="44"  cy="-655" r="5"    fill="rgba(255,255,255,0.82)"/>

    <!-- Celery stalk -->
    <path d="M 8 -648  Q 22 -718  18 -805"
          stroke="url(#celGrad)" stroke-width="13"
          fill="none" stroke-linecap="round"/>
    <!-- Celery inner vein highlight -->
    <path d="M 10 -648  Q 24 -718  20 -805"
          stroke="rgba(180,255,120,0.28)" stroke-width="5"
          fill="none" stroke-linecap="round"/>

    <!-- Celery leaves -->
    <ellipse cx="15"  cy="-808" rx="28" ry="17" fill="#3A8A28"
             transform="rotate(-22 15 -808)"/>
    <ellipse cx="32"  cy="-790" rx="22" ry="14" fill="#4CAA38"
             transform="rotate(16 32 -790)"/>
    <ellipse cx="-1"  cy="-790" rx="20" ry="13" fill="#3A8A28"
             transform="rotate(-38 -1 -790)"/>
    <!-- Leaf centre veins -->
    <line x1="12"  y1="-812" x2="8"   y2="-796"
          stroke="rgba(255,255,255,0.18)" stroke-width="2"/>
    <line x1="30"  y1="-794" x2="22"  y2="-778"
          stroke="rgba(255,255,255,0.18)" stroke-width="2"/>

    <!-- Lemon wedge (left rim) -->
    <g transform="translate(-57,-655) rotate(8)">
      <!-- Peel -->
      <path d="M 0 0  L 0 -54  A 54 54 0 0 0 -46.8 -27  Z"
            fill="#F5C518" stroke="#C8A000" stroke-width="1.5"/>
      <!-- Flesh -->
      <path d="M 0 -7  L 0 -46  A 46 46 0 0 0 -39.8 -23  Z"
            fill="#FFE055" fill-opacity="0.75"/>
      <!-- White pith -->
      <path d="M 0 -46  A 46 46 0 0 0 -39.8 -23"
            stroke="rgba(255,255,255,0.78)" stroke-width="7"
            fill="none" stroke-linecap="round"/>
      <!-- Segment lines -->
      <line x1="0" y1="-7"  x2="-20"  y2="-42"
            stroke="#C8A000" stroke-width="1.2" stroke-opacity="0.4"/>
      <line x1="0" y1="-7"  x2="-38"  y2="-22"
            stroke="#C8A000" stroke-width="1.2" stroke-opacity="0.4"/>
    </g>

  </g><!-- end bloody mary -->


  <!-- ══════════════════════════════════════════
       CLINK STARBURST  ≈ (512, 242)
       ══════════════════════════════════════════ -->
  <g transform="translate(512,242)" filter="url(#clinkGlow)">
    <!-- Soft outer orb -->
    <circle cx="0" cy="0" r="42" fill="#FF6B47" fill-opacity="0.22"/>

    <!-- 6 long primary rays (every 60°) -->
    <line x1="0"     y1="-72" x2="0"     y2="72"  stroke="#FF6B47" stroke-width="6" stroke-linecap="round"/>
    <line x1="-62.4" y1="-36" x2="62.4"  y2="36"  stroke="#FF6B47" stroke-width="6" stroke-linecap="round"/>
    <line x1="-62.4" y1="36"  x2="62.4"  y2="-36" stroke="#FF6B47" stroke-width="6" stroke-linecap="round"/>

    <!-- 6 short secondary rays (rotated 30° from primary) -->
    <g transform="rotate(30)">
      <line x1="0"     y1="-44" x2="0"     y2="44"  stroke="#FF6B47" stroke-width="4" stroke-linecap="round" stroke-opacity="0.72"/>
      <line x1="-38.1" y1="-22" x2="38.1"  y2="22"  stroke="#FF6B47" stroke-width="4" stroke-linecap="round" stroke-opacity="0.72"/>
      <line x1="-38.1" y1="22"  x2="38.1"  y2="-22" stroke="#FF6B47" stroke-width="4" stroke-linecap="round" stroke-opacity="0.72"/>
    </g>

    <!-- Centre dot -->
    <circle cx="0" cy="0" r="14" fill="#FF6B47"/>
    <circle cx="0" cy="0" r="7"  fill="white" fill-opacity="0.6"/>
  </g>

</svg>
"""


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root  = os.path.dirname(script_dir)
    svg_path   = "/tmp/squad_brunch_icon.svg"
    png_path   = "/tmp/squad_brunch_icon.png"
    dest       = os.path.join(
        repo_root,
        "meetup-ios/Assets.xcassets/AppIcon.appiconset",
        "Icon-iOS-Default-1024x1024@1x.png",
    )

    with open(svg_path, "w") as f:
        f.write(build_svg())

    result = subprocess.run(
        ["rsvg-convert", "-w", "1024", "-h", "1024", svg_path, "-o", png_path],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"rsvg-convert error:\n{result.stderr}")
        return 1

    shutil.copy(png_path, dest)
    print(f"Icon written to:\n  {dest}")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
