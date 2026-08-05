/**
 * M0 acceptance — Picking-Smoke (A-M0-6, A-M0-10, A-M0-12).
 * Contract tests owned by the Reviewer (docs/12 §1). Red before build is expected.
 *
 * Picking contract (CRITERIA.json O-M0-4 (b)):
 *   src/world/index.ts exports
 *     pickCountryAt(latRad: number, lonRad: number): string | null   // ISO3
 * (Datenebene des Farb-ID-Pickings; Winkel in Radiant — IMPLEMENTATION-RULES
 * §Einheiten. Die UI-Ebene „Klick → Name/ISO3 im Overlay" wird zusätzlich vom
 * smoke/shots-Gate abgedeckt.)
 *
 * Grounding without external coordinates (CRITERIA.json O-M0-1): test points
 * are derived from countries.topo.json itself with the reviewer's OWN
 * TopoJSON decoder + point-in-polygon oracle (helpers.ts) — builder picking
 * and reviewer geometry must agree (docs/12 §7a.4).
 */
import { describe, expect, it } from 'vitest'

// Contract import — implemented by the Builder in M0 BUILD phase.
import { pickCountryAt } from '../../src/world'
import {
  bboxOf,
  decodeCountryShapes,
  degToRad,
  interiorPointOf,
  loadCountriesMeta,
  loadCountriesTopo,
  outerRingArea,
  pointInShape,
  type CountryShape,
  type LonLat,
} from './helpers'

type SamplePoint = { iso3: string; point: LonLat }

function collectSamples(): { shapes: CountryShape[]; samples: SamplePoint[] } {
  const meta = loadCountriesMeta()
  const metaIso3 = new Set(meta.map((c) => c.iso3))
  const shapes = decodeCountryShapes(loadCountriesTopo()).filter((s) => s.iso3 !== '')

  const samples: SamplePoint[] = []
  const eligible = shapes
    .filter((shape) => metaIso3.has(shape.iso3))
    // Skip antimeridian-spanning shapes — the planar oracle is not valid there.
    .filter((shape) => {
      const box = bboxOf(shape.polygons)
      return box.lonMax - box.lonMin <= 180
    })
    .sort((a, b) => (a.iso3 < b.iso3 ? -1 : 1))

  for (const shape of eligible) {
    if (samples.length >= 6) break
    const largest = [...shape.polygons].sort((a, b) => outerRingArea(b) - outerRingArea(a))[0]
    if (largest === undefined) continue
    const point = interiorPointOf(largest)
    if (point === null) continue
    // Border safety: the point must lie in exactly this country's geometry.
    const ambiguous = shapes.some((other) => other !== shape && pointInShape(point, other.polygons))
    if (ambiguous) continue
    samples.push({ iso3: shape.iso3, point })
  }
  return { shapes, samples }
}

describe('A-M0-6 / A-M0-10 / A-M0-12: Land anklickbar — Picking-Smoke', () => {
  it('topology yields at least 3 unambiguous interior sample points', () => {
    const { samples } = collectSamples()
    expect(samples.length).toBeGreaterThanOrEqual(3)
  })

  it('pickCountryAt returns the correct ISO3 for interior points of sampled countries', () => {
    const { samples } = collectSamples()
    for (const { iso3, point } of samples) {
      const [lonDeg, latDeg] = point
      expect(pickCountryAt(degToRad(latDeg), degToRad(lonDeg)), `${iso3} @ ${latDeg},${lonDeg}`).toBe(
        iso3,
      )
    }
  })

  it('A-M0-6: picked ISO3 resolves to a display name for the overlay (Name/ISO3)', () => {
    const meta = loadCountriesMeta()
    const byIso3 = new Map(meta.map((c) => [c.iso3, c]))
    const { samples } = collectSamples()
    for (const { iso3 } of samples) {
      const country = byIso3.get(iso3)
      expect(country, `${iso3} missing in countries.meta.json`).toBeDefined()
      expect(country!.name.length).toBeGreaterThan(0)
    }
  })

  it('picking open water returns null', () => {
    const { shapes } = collectSamples()
    // Candidate open-water points ([lonDeg, latDeg]); the reviewer oracle
    // verifies against the topology that the chosen one is in NO country —
    // the assertion rests on the data, not on the literals.
    const candidates: LonLat[] = [
      [-25, 0],
      [-130, -45],
      [85, -35],
      [-150, 35],
    ]
    const ocean = candidates.find(
      (pt) => !shapes.some((shape) => pointInShape(pt, shape.polygons)),
    )
    expect(ocean, 'no candidate point is open water per the topology').toBeDefined()
    const [lonDeg, latDeg] = ocean!
    expect(pickCountryAt(degToRad(latDeg), degToRad(lonDeg))).toBeNull()
  })
})

describe('A-M0-3: Zentroide liegen im Umriss-Rahmen ihres Landes', () => {
  it('every sampled country centroid falls inside its bbox (consistency meta ↔ topo)', () => {
    const meta = loadCountriesMeta()
    const shapesByIso3 = new Map(
      decodeCountryShapes(loadCountriesTopo())
        .filter((s) => s.iso3 !== '')
        .map((s) => [s.iso3, s]),
    )
    let checked = 0
    for (const country of meta) {
      const shape = shapesByIso3.get(country.iso3)
      if (shape === undefined) continue
      const box = bboxOf(shape.polygons)
      if (box.lonMax - box.lonMin > 180) continue // antimeridian — planar bbox invalid
      const [latDeg, lonDeg] = country.centroid
      expect(latDeg, `${country.iso3} centroid lat`).toBeGreaterThanOrEqual(box.latMin)
      expect(latDeg, `${country.iso3} centroid lat`).toBeLessThanOrEqual(box.latMax)
      expect(lonDeg, `${country.iso3} centroid lon`).toBeGreaterThanOrEqual(box.lonMin)
      expect(lonDeg, `${country.iso3} centroid lon`).toBeLessThanOrEqual(box.lonMax)
      checked++
    }
    expect(checked).toBeGreaterThan(0)
  })
})
