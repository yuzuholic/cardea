'use client'

// ported from heuresis/web (components/brand/landscape-banner.tsx): the summer triangle
// under a viewfinder. only the text defaults and the two helpers below differ.
import { useEffect, useRef } from "react"
import { animate } from "animejs"

function reducedMotion(): boolean {
  return typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches
}

type Props = {
  className?: string
  title?: string
  subtitle?: string
  trackMouse?: boolean
}

// The drawing lives in the artwork's own 680 x 460 space (the figure is centred on x = 340,
// y = 230). The grid is generated well beyond it in both directions, and the SVG is sliced
// to the viewport, so at any width the figure stays centred and the grid runs edge to edge.
const GRID_STEP = 60
const GRID_SPAN = 4000
const TOP = 40
const BOTTOM = 420

// A field of small four-point stars scattered across the whole grid, deterministic so the
// sky is the same on every load. They stay faint and small next to the three main stars.
function starPath(cx: number, cy: number, size: number): string {
  const inner = size * 0.32
  return `M${cx} ${cy - size} L${cx + inner} ${cy - inner} L${cx + size} ${cy} L${cx + inner} ${cy + inner} L${cx} ${cy + size} L${cx - inner} ${cy + inner} L${cx - size} ${cy} L${cx - inner} ${cy - inner} Z`
}

function seededRandom(seed: number) {
  let state = seed >>> 0
  return () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0
    return state / 4294967296
  }
}

// An endless field: stars are laid out on a repeating tile (deterministic per layer), the
// tile is used as an SVG pattern over the whole banner, and the pattern is slid along a
// tilted axis forever. Two layers at different speeds and sizes give parallax depth.
const TILE = { w: 1400, h: 700 }
const FIELD_TILT_DEGREES = -12
const FIELD_LAYERS = [
  { id: "far", count: 120, sizeMin: 0.9, sizeMax: 2.0, opacity: 0.32, seconds: 220 },
  { id: "near", count: 45, sizeMin: 2.2, sizeMax: 4.2, opacity: 0.5, seconds: 120 },
]

function tileStars(seed: number, count: number, sizeMin: number, sizeMax: number) {
  const next = seededRandom(seed)
  return Array.from({ length: count }, () => ({
    x: next() * TILE.w,
    y: next() * TILE.h,
    size: sizeMin + next() * (sizeMax - sizeMin),
    opacity: 0.4 + next() * 0.6,
  }))
}

const fieldTiles = FIELD_LAYERS.map((layer, index) => ({ ...layer, stars: tileStars(101 + index * 17, layer.count, layer.sizeMin, layer.sizeMax) }))

const verticals: number[] = []
for (let x = 340 - GRID_SPAN; x <= 340 + GRID_SPAN; x += GRID_STEP) if (x !== 340) verticals.push(x)
const horizontals = [110, 170, 290, 350, 410]

const DIGIT_HEIGHT = 12

function DigitSlot({ axis, slot, x }: { axis: "x" | "y"; slot: number; x: number }) {
  // One rolling digit: a clip window with two glyphs, the current one and the incoming one.
  const id = `digit-${axis}-${slot}`
  return (
    <g data-digit={`${axis}${slot}`} clipPath={`url(#${id})`}>
      <defs>
        <clipPath id={id}>
          <rect x={x - 1} y={402 - DIGIT_HEIGHT + 2} width={8} height={DIGIT_HEIGHT + 2} />
        </clipPath>
      </defs>
      <text data-current x={x} y={402}>
        {axis === "x" ? "340"[slot] : "230"[slot]}
      </text>
      <text data-incoming x={x} y={402} opacity={0} />
    </g>
  )
}

const rolling = new WeakMap<Element, ReturnType<typeof animate>[]>()

function rollDigits(group: SVGGElement, value: number, previous: number, axis: "x" | "y") {
  // Rolls only the digits that changed, upward for an increase and downward for a decrease.
  const next = String(Math.max(0, Math.min(999, value))).padStart(3, " ")
  const before = String(Math.max(0, Math.min(999, previous))).padStart(3, " ")
  const direction = value >= previous ? -1 : 1
  for (let slot = 0; slot < 3; slot += 1) {
    if (next[slot] === before[slot]) continue
    const cell = group.querySelector<SVGGElement>(`[data-digit="${axis}${slot}"]`)
    if (!cell) continue
    const current = cell.querySelector<SVGTextElement>("[data-current]")
    const incoming = cell.querySelector<SVGTextElement>("[data-incoming]")
    if (!current || !incoming) continue
    for (const running of rolling.get(cell) ?? []) running.pause()
    current.textContent = before[slot]
    current.style.transform = ""
    current.style.opacity = "1"
    incoming.textContent = next[slot]
    const out = animate(current, { translateY: [0, direction * DIGIT_HEIGHT], opacity: [1, 0], duration: 180, ease: "outQuad" })
    const inward = animate(incoming, {
      translateY: [-direction * DIGIT_HEIGHT, 0],
      opacity: [0, 1],
      duration: 180,
      ease: "outQuad",
      onComplete: () => {
        current.textContent = next[slot]
        current.style.transform = ""
        current.style.opacity = "1"
        incoming.style.opacity = "0"
        incoming.style.transform = ""
      },
    })
    rolling.set(cell, [out, inward])
  }
}

const STARS = [
  { name: "VEGA", x: 268, y: 158, size: 14, ring: 24 },
  { name: "DENEB", x: 418, y: 176, size: 9, ring: 14 },
  { name: "ALTAIR", x: 358, y: 320, size: 12, ring: 19 },
]
const LOCK_RADIUS = 34
const CENTRE_LOCK = -1
const CENTRE_LOCK_RADIUS = 26

// The sky turns rigidly about the celestial pole. For a banner the pole sits far above the
// centre, so a small swing is almost pure sideways travel with only a degree or so of tilt,
// and it goes back and forth rather than wheeling off the page.
const POLE = { x: 340, y: -8000 }
const SWING_DEGREES = 1.5
const SWING_SECONDS = 135

function rotateAbout(x: number, y: number, degrees: number): { x: number; y: number } {
  const radians = (degrees * Math.PI) / 180
  const dx = x - POLE.x
  const dy = y - POLE.y
  return { x: POLE.x + dx * Math.cos(radians) - dy * Math.sin(radians), y: POLE.y + dx * Math.sin(radians) + dy * Math.cos(radians) }
}

const CENTRE = { x: 340, y: 230 }
const CORNER_REACH = { x: 300, y: 165 }

export function LandscapeBanner({ className, title = "Cardea", subtitle = "the hinge the gate swings on", trackMouse = true }: Props) {
  const svg = useRef<SVGSVGElement>(null)

  const skyAngle = useRef(0)

  useEffect(() => {
    // Diurnal motion: the whole sky - background stars, the triangle, its rings and edges -
    // turns rigidly about the pole. The frame, grid and drafting marks are the instrument
    // and stay put.
    const node = svg.current
    if (!node || reducedMotion()) return
    const rotor = node.querySelector<SVGGElement>("[data-rotor]")
    if (!rotor) return
    const state = { angle: -SWING_DEGREES }
    const turn = animate(state, {
      angle: SWING_DEGREES,
      duration: SWING_SECONDS * 1000,
      ease: "inOutSine",
      alternate: true,
      loop: true,
      onUpdate: () => {
        skyAngle.current = state.angle
        rotor.setAttribute("transform", `rotate(${state.angle} ${POLE.x} ${POLE.y})`)
      },
    })
    return () => {
      turn.pause()
    }
  }, [])

  useEffect(() => {
    // The endless field slides along its tilted axis: each layer's pattern is translated by
    // one tile width and wraps, so it never runs out.
    const node = svg.current
    if (!node || reducedMotion()) return
    const slides = fieldTiles.map((layer) => {
      const pattern = node.querySelector<SVGPatternElement>(`[data-field="${layer.id}"]`)
      const state = { shift: 0 }
      return animate(state, {
        shift: TILE.w,
        duration: layer.seconds * 1000,
        ease: "linear",
        loop: true,
        onUpdate: () => pattern?.setAttribute("patternTransform", `rotate(${FIELD_TILT_DEGREES}) translate(${state.shift} 0)`),
      })
    })
    return () => {
      slides.forEach((slide) => slide.pause())
    }
  }, [])

  useEffect(() => {
    // Scintillation: every star flickers a little, quickly and at random - stronger for the
    // brighter ones - the way the atmosphere makes them do.
    const node = svg.current
    if (!node || reducedMotion()) return
    const next = seededRandom(11)
    const twinkles = [
      ...Array.from(node.querySelectorAll<SVGPathElement>("[data-star]")).map((star) =>
        animate(star, {
          opacity: [1, 0.78 + next() * 0.1, 1, 0.9, 1],
          duration: 1400 + next() * 1800,
          delay: next() * 1200,
          ease: "inOutSine",
          loop: true,
        }),
      ),
    ]
    return () => {
      twinkles.forEach((twinkle) => twinkle.pause())
    }
  }, [])

  useEffect(() => {
    // The four corner brackets are a viewfinder: they glide toward the mouse (in the
    // drawing's own units, so it works at any size) and settle back to centre on leave.
    const node = svg.current
    if (!node || !trackMouse || reducedMotion()) return
    const corners = node.querySelector<SVGGElement>("[data-corners]")
    const labels = node.querySelector<SVGGElement>("[data-labels]")
    const coords = node.querySelector<SVGGElement>("[data-coords]")
    if (!corners || !labels) return

    let shown = { x: CENTRE.x, y: CENTRE.y }
    let locked: number | null = null

    const edgesOf = (index: number) =>
      Array.from(node.querySelectorAll<SVGLineElement>("[data-edge]")).filter((edge) => (edge.dataset.edge ?? "").split("-").includes(String(index)))

    const lockOn = (index: number) => {
      const ring = node.querySelector<SVGGElement>(`[data-lock="${index}"]`)
      const star = node.querySelector<SVGPathElement>(`[data-star="${index}"]`)
      if (!ring || !star) return
      // a quick double blink, then hold; the star itself pulses once
      animate(ring, { opacity: [0, 1, 0.2, 1, 0.3, 1], duration: 620, ease: "linear" })
      animate(star, { scale: [1, 1.5, 1], duration: 420, ease: "outBack" })
      for (const edge of edgesOf(index)) {
        const length = edge.getTotalLength()
        edge.style.strokeDasharray = edge.getAttribute("stroke-dasharray") ? "6 6" : `${length}`
        animate(edge, { opacity: [0, edge.getAttribute("stroke-width") === "2.5" ? 0.9 : 0.4], duration: 500, delay: 200, ease: "outQuad" })
      }
    }

    const release = (index: number) => {
      const ring = node.querySelector<SVGGElement>(`[data-lock="${index}"]`)
      if (ring) animate(ring, { opacity: 0, duration: 260, ease: "outQuad" })
      for (const edge of edgesOf(index)) animate(edge, { opacity: 0, duration: 260, ease: "outQuad" })
    }

    const deco = node.querySelector<SVGGElement>("[data-deco]")
    const construction = node.querySelector<SVGGElement>("[data-construction]")
    const frameTicks = node.querySelector<SVGGElement>("[data-frame-ticks]")
    const showFrameTicks = (on: boolean) => {
      if (frameTicks) animate(frameTicks, { opacity: on ? [0, 1, 0.3, 1] : 0, duration: on ? 520 : 260, ease: on ? "linear" : "outQuad" })
    }
    const skeleton = node.querySelector<SVGGElement>("[data-skeleton]")
    const titleText = node.querySelector<SVGGElement>("[data-title-text]")
    const titleBlur = node.querySelector<SVGFEGaussianBlurElement>("[data-title-blur]")
    const subtitleText = node.querySelector<SVGTextElement>("[data-subtitle]")
    const blur = { amount: 3 }

    const resolveTitle = (label: string) => {
      // The name block sharpens from a blurred skeleton into the real text once locked on.
      if (subtitleText) subtitleText.textContent = label
      animate(blur, { amount: 0, duration: 520, ease: "outCubic", onUpdate: () => titleBlur?.setAttribute("stdDeviation", blur.amount.toFixed(2)) })
      if (titleText) animate(titleText, { opacity: 1, duration: 420, ease: "outQuad" })
      if (skeleton) animate(skeleton, { opacity: 0, duration: 300, ease: "outQuad" })
    }

    const blurTitle = () => {
      animate(blur, { amount: 3, duration: 420, ease: "outCubic", onUpdate: () => titleBlur?.setAttribute("stdDeviation", blur.amount.toFixed(2)) })
      if (titleText) animate(titleText, { opacity: 0.35, duration: 320, ease: "outQuad" })
      if (skeleton) animate(skeleton, { opacity: 0.18, duration: 320, ease: "outQuad" })
    }

    const lockCentre = () => {
      // Dead centre: every ring, every edge and all the drafting marks come back at once.
      STARS.forEach((_, index) => lockOn(index))
      if (deco) animate(deco, { opacity: [0, 1, 0.3, 1], duration: 620, ease: "linear" })
      if (construction) animate(construction, { opacity: [0, 1, 0.3, 1], duration: 620, ease: "linear" })
    }

    const releaseCentre = () => {
      STARS.forEach((_, index) => release(index))
      if (deco) animate(deco, { opacity: 0, duration: 300, ease: "outQuad" })
      if (construction) animate(construction, { opacity: 0, duration: 300, ease: "outQuad" })
    }

    const updateLock = (x: number, y: number) => {
      let nearest: number | null = null
      const centreNow = rotateAbout(CENTRE.x, CENTRE.y, skyAngle.current)
      if (Math.hypot(centreNow.x - x, centreNow.y - y) < CENTRE_LOCK_RADIUS) {
        nearest = CENTRE_LOCK
      } else {
        let best = LOCK_RADIUS
        STARS.forEach((star, index) => {
          const now = rotateAbout(star.x, star.y, skyAngle.current)
          const distance = Math.hypot(now.x - x, now.y - y)
          if (distance < best) {
            best = distance
            nearest = index
          }
        })
      }
      if (nearest === locked) return
      if (locked === CENTRE_LOCK) releaseCentre()
      else if (locked !== null) release(locked)
      locked = nearest
      if (locked === CENTRE_LOCK) {
        lockCentre()
        resolveTitle(subtitle)
        showFrameTicks(true)
      } else if (locked !== null) {
        lockOn(locked)
        resolveTitle(`LOCK · ${STARS[locked].name}`)
        showFrameTicks(true)
      } else {
        blurTitle()
        showFrameTicks(false)
      }
    }

    const offset = { x: 0, y: 0 }
    let animation: ReturnType<typeof animate> | null = null

    const glideTo = (x: number, y: number, duration: number) => {
      animation?.pause()
      animation = animate(offset, {
        x,
        y,
        duration,
        ease: "outQuint",
        onUpdate: () => {
          const transform = `translate(${offset.x} ${offset.y})`
          corners.setAttribute("transform", transform)
          labels.setAttribute("transform", transform)
          if (coords) {
            const x = Math.round(CENTRE.x + offset.x)
            const y = Math.round(CENTRE.y + offset.y)
            if (x !== shown.x) rollDigits(coords, x, shown.x, "x")
            if (y !== shown.y) rollDigits(coords, y, shown.y, "y")
            shown = { x, y }
          }
        },
      })
    }

    let lastPointer = { x: CENTRE.x, y: CENTRE.y }
    const recheck = window.setInterval(() => updateLock(lastPointer.x, lastPointer.y), 400)

    const onMove = (event: MouseEvent) => {
      const matrix = node.getScreenCTM()
      if (!matrix) return
      const point = new DOMPoint(event.clientX, event.clientY).matrixTransform(matrix.inverse())
      const x = Math.max(-CORNER_REACH.x, Math.min(CORNER_REACH.x, point.x - CENTRE.x))
      const y = Math.max(-CORNER_REACH.y, Math.min(CORNER_REACH.y, point.y - CENTRE.y))
      glideTo(x, y, 900)
      lastPointer = { x: CENTRE.x + x, y: CENTRE.y + y }
      updateLock(lastPointer.x, lastPointer.y)
    }
    const onLeave = () => {
      glideTo(0, 0, 1200)
      lastPointer = { x: CENTRE.x, y: CENTRE.y }
      updateLock(lastPointer.x, lastPointer.y)
    }

    node.addEventListener("mousemove", onMove)
    node.addEventListener("mouseleave", onLeave)
    return () => {
      node.removeEventListener("mousemove", onMove)
      node.removeEventListener("mouseleave", onLeave)
      window.clearInterval(recheck)
      animation?.pause()
    }
  }, [trackMouse, subtitle])

  return (
    <svg
      ref={svg}
      viewBox={`${340 - GRID_SPAN} ${TOP} ${GRID_SPAN * 2} ${BOTTOM - TOP}`}
      preserveAspectRatio="xMidYMid slice"
      role="img"
      aria-label={title}
      className={`block h-full w-full text-fd-foreground ${className ?? ""}`}
      data-banner
    >
      <defs>
        {fieldTiles.map((layer) => (
          <pattern
            key={layer.id}
            id={`starfield-${layer.id}`}
            data-field={layer.id}
            width={TILE.w}
            height={TILE.h}
            patternUnits="userSpaceOnUse"
            patternTransform={`rotate(${FIELD_TILT_DEGREES}) translate(0 0)`}
          >
            <g fill="currentColor" opacity={layer.opacity}>
              {layer.stars.map((star, index) => (
                <path key={index} d={starPath(star.x, star.y, star.size)} opacity={star.opacity} />
              ))}
            </g>
          </pattern>
        ))}
      </defs>
      {fieldTiles.map((layer) => (
        <rect key={layer.id} x={340 - GRID_SPAN} y={TOP - 400} width={GRID_SPAN * 2} height={BOTTOM - TOP + 800} fill={`url(#starfield-${layer.id})`} className="text-fd-foreground" />
      ))}

      <g data-grid stroke="currentColor" strokeWidth="1" opacity="0.06">
        {verticals.map((x) => (
          <line key={x} x1={x} y1={TOP} x2={x} y2={BOTTOM} />
        ))}
        {horizontals.map((y) => (
          <line key={y} x1={340 - GRID_SPAN} y1={y} x2={340 + GRID_SPAN} y2={y} />
        ))}
      </g>

      <g data-rotor>

      <g data-construction stroke="currentColor" fill="none" opacity="0">
        <g strokeWidth="2" strokeDasharray="8 8" opacity="0.26">
          <line x1="230" y1="350" x2="440" y2="110" />
          <line x1="280" y1="380" x2="490" y2="140" />
        </g>
        <g strokeWidth="1" opacity="0.45">
          <line x1="262" y1="169" x2="244" y2="179" />
          <line x1="352" y1="331" x2="334" y2="341" />
          <line x1="244" y1="179" x2="334" y2="341" />
          <line x1="240" y1="175" x2="248" y2="183" />
          <line x1="330" y1="337" x2="338" y2="345" />
        </g>
      </g>

      <g data-edges stroke="currentColor" fill="none">
        <line data-edge="0-2" x1="268" y1="158" x2="358" y2="320" strokeWidth="2.5" opacity="0" />
        <line data-edge="0-1" x1="268" y1="158" x2="418" y2="176" strokeWidth="1.5" strokeDasharray="6 6" opacity="0" />
        <line data-edge="1-2" x1="418" y1="176" x2="358" y2="320" strokeWidth="1.5" strokeDasharray="6 6" opacity="0" />
      </g>

      {STARS.map((star, index) => (
        <g key={index} data-lock={index} opacity="0" stroke="currentColor" fill="none">
          <circle cx={star.x} cy={star.y} r={star.ring} strokeWidth="1.2" strokeDasharray="3 4" opacity="0.6" />
          <g strokeWidth={index === 1 ? 1.5 : 2} opacity="0.7">
            <line x1={star.x} y1={star.y - star.ring - 12} x2={star.x} y2={star.y - star.ring} />
            <line x1={star.x} y1={star.y + star.ring} x2={star.x} y2={star.y + star.ring + 12} />
            <line x1={star.x - star.ring - 12} y1={star.y} x2={star.x - star.ring} y2={star.y} />
            <line x1={star.x + star.ring} y1={star.y} x2={star.x + star.ring + 12} y2={star.y} />
          </g>
          <text
            x={star.x + star.ring + 18}
            y={star.y - star.ring - 4}
            fontFamily="ui-monospace, 'Cascadia Mono', Menlo, Consolas, monospace"
            fontSize="10"
            fill="currentColor"
            stroke="none"
            opacity="0.7"
          >
            {star.name}
          </text>
        </g>
      ))}

      <g data-stars fill="currentColor">
        {STARS.map((star, index) => (
          <path key={index} data-star={index} d={starPath(star.x, star.y, star.size)} style={{ transformOrigin: `${star.x}px ${star.y}px`, transformBox: "view-box" }} />
        ))}
      </g>
      </g>

      <g data-corners stroke="currentColor" strokeWidth="2" fill="none" opacity="0.9">
        <path d="M56 72 L56 56 L72 56" />
        <path d="M608 56 L624 56 L624 72" />
        <path d="M624 388 L624 404 L608 404" />
        <path d="M72 404 L56 404 L56 388" />
        <g data-frame-ticks strokeWidth="1.5" opacity="0">
          <line x1="340" y1="56" x2="340" y2="68" />
          <line x1="340" y1="392" x2="340" y2="404" />
          <line x1="56" y1="230" x2="68" y2="230" />
          <line x1="612" y1="230" x2="624" y2="230" />
        </g>
      </g>

      <g data-deco stroke="currentColor" fill="none" opacity="0">
        <g strokeWidth="1" opacity="0.14" strokeDasharray="4 6">
          <line x1={340 - GRID_SPAN} y1="230" x2={340 + GRID_SPAN} y2="230" />
          <line x1="340" y1={TOP} x2="340" y2={BOTTOM} />
        </g>
        <g strokeWidth="1" opacity="0.35">
          <line x1="112" y1="96" x2="128" y2="96" />
          <line x1="120" y1="88" x2="120" y2="104" />
          <line x1="548" y1="352" x2="564" y2="352" />
          <line x1="556" y1="344" x2="556" y2="360" />
        </g>
      </g>


      <g data-labels fontFamily="ui-monospace, 'Cascadia Mono', Menlo, Consolas, monospace">
        <defs>
          <filter id="title-blur" x="-20%" y="-50%" width="140%" height="200%">
            <feGaussianBlur data-title-blur stdDeviation="3" />
          </filter>
        </defs>
        <g data-skeleton fill="currentColor" opacity="0.18">
          <rect x="64" y="63" width="58" height="10" rx="3" />
          <rect x="64" y="80" width="132" height="8" rx="3" />
        </g>
        <g data-title-text filter="url(#title-blur)" opacity="0.35">
          <text x="64" y="72" fontSize="12" fontWeight="500" fill="currentColor">
            {title}
          </text>
          <text data-subtitle x="64" y="88" fontSize="11" fill="currentColor" opacity="0.7">
            {subtitle}
          </text>
        </g>
        <g data-coords fontSize="11" fill="currentColor" opacity="0.4">
          <text x="64" y="402">x</text>
          {[0, 1, 2].map((slot) => (
            <DigitSlot key={`x${slot}`} axis="x" slot={slot} x={72 + slot * 7} />
          ))}
          <text x="104" y="402">y</text>
          {[0, 1, 2].map((slot) => (
            <DigitSlot key={`y${slot}`} axis="y" slot={slot} x={112 + slot * 7} />
          ))}
        </g>
        <text x="616" y="402" textAnchor="end" fontSize="11" fill="currentColor" opacity="0.55">
          1024 x 1024
        </text>
      </g>
    </svg>
  )
}
