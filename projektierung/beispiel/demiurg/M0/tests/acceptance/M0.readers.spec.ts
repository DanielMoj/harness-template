/**
 * M0 acceptance — pipeline outputs and binary readers (A-M0-3, A-M0-4, A-M0-11).
 * Contract tests owned by the Reviewer (docs/12 §1). Red before build is expected.
 *
 * Reader contract (CRITERIA.json O-M0-4 (a)):
 *   src/data/index.ts exports
 *     parseBinHeader(buf: ArrayBuffer): { magic: string; version: number; dims: number[] }
 *     readDistMatrix(buf: ArrayBuffer): { n: number; km: Float32Array }
 *
 * The distance oracle below is the reviewer's INDEPENDENT implementation
 * (haversine on the anchored sphere radius) — builder code and oracle must
 * agree within tolerance (docs/12 §7a.4).
 */
import { existsSync, readFileSync } from 'node:fs'
import { describe, expect, it, vi } from 'vitest'

// Der dist.bin-Invarianten-Zeuge (489 ms nativ, Asset-IO) liegt unter
// Parallellast des Mutations-Dry-Runs nahe der vitest-5000-ms-Kante
// (M6-E22-/E24-Familie). Reine Hänger-Schwellen-Kalibrierung, keine
// Assertion-Änderung (REVIEW M10 r9, E22/R9-4).
vi.setConfig({ testTimeout: 60_000 })

// Contract import — implemented by the Builder in M0 BUILD phase.
import { parseBinHeader, readDistMatrix } from '../../src/data'
import {
  anchorNumber,
  approxRel,
  degToRad,
  haversineKm,
  listFilesRecursive,
  loadCountriesMeta,
  loadCountriesTopo,
  repoPath,
} from './helpers'

const toArrayBuffer = (buf: Buffer): ArrayBuffer =>
  buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) as ArrayBuffer

const readAsset = (...parts: string[]): ArrayBuffer =>
  toArrayBuffer(readFileSync(repoPath('public', 'assets', ...parts)))

// Anchors (reference/anchors/*.json — AGENTS.md Integrität rule 7).
const EARTH_RADIUS_KM = anchorNumber('M0-earth-radius-km')
const HEADER_BYTES = anchorNumber('M0-bin-header-bytes')
const BYTES_PER_VALUE = anchorNumber('M0-dist-bin-bytes-per-value')
const COUNTRY_COUNT_NOMINAL = anchorNumber('M0-country-count-nominal')

describe('A-M0-3: Terrain-Heightmap, countries.topo.json, Zentroide, Distanzmatrix', () => {
  it('all M0 pipeline outputs exist under public/assets/', () => {
    const outputs = [
      ['terrain', 'globe_height_4096.png'],
      ['world', 'countries.topo.json'],
      ['world', 'countries.meta.json'],
      ['world', 'dist.bin'],
    ]
    for (const parts of outputs) {
      expect(existsSync(repoPath('public', 'assets', ...parts)), parts.join('/')).toBe(true)
    }
  })

  it('globe_height_4096.png is a 16-bit equirect heightmap, 4096 wide (docs/03)', () => {
    const png = readFileSync(repoPath('public', 'assets', 'terrain', 'globe_height_4096.png'))
    // PNG signature per the PNG spec.
    expect([...png.subarray(0, 8)]).toEqual([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    const width = png.readUInt32BE(16)
    const height = png.readUInt32BE(20)
    const bitDepth = png.readUInt8(24)
    // 4096 from the asset name fixed in docs/03; equirect ⇒ height = width/2.
    expect(width).toBe(4096)
    expect(height).toBe(width / 2)
    expect(bitDepth).toBe(16)
  })

  it('countries.meta.json has valid ISO3, Name, Zentroid und Nachbarn per Land (docs/03)', () => {
    const meta = loadCountriesMeta()
    expect(meta.length).toBeGreaterThan(0)
    const seen = new Set<string>()
    for (const country of meta) {
      expect(country.iso3, `${country.name}: iso3`).toMatch(/^[A-Z]{3}$/)
      expect(seen.has(country.iso3), `duplicate iso3 ${country.iso3}`).toBe(false)
      seen.add(country.iso3)
      expect(typeof country.name).toBe('string')
      expect(country.name.length).toBeGreaterThan(0)
      const [latDeg, lonDeg] = country.centroid
      expect(latDeg).toBeGreaterThanOrEqual(-90)
      expect(latDeg).toBeLessThanOrEqual(90)
      expect(lonDeg).toBeGreaterThanOrEqual(-180)
      expect(lonDeg).toBeLessThanOrEqual(180)
      expect(Array.isArray(country.neighbors)).toBe(true)
    }
  })

  it('country count is consistent across meta and topo, near the nominal ~200 (O-M0-3)', () => {
    const meta = loadCountriesMeta()
    const topo = loadCountriesTopo()
    let geometryCount = 0
    for (const object of Object.values(topo.objects)) {
      geometryCount += Array.isArray(object.geometries) ? object.geometries.length : 1
    }
    expect(geometryCount).toBe(meta.length)
    // Plausibility band ±50 % around the spec's nominal value ("~200",
    // docs/01) — exact cardinality is a PLAN decision, see O-M0-3.
    expect(meta.length).toBeGreaterThanOrEqual(COUNTRY_COUNT_NOMINAL * 0.5)
    expect(meta.length).toBeLessThanOrEqual(COUNTRY_COUNT_NOMINAL * 1.5)
  })
})

describe('A-M0-11: Reader-Tests — 16-B-Header und dist.bin (contracts/PROTOCOLS.md §4)', () => {
  it('parseBinHeader reads magic/version/dims from the common 16-byte header', () => {
    const buf = readAsset('world', 'dist.bin')
    expect(buf.byteLength).toBeGreaterThanOrEqual(HEADER_BYTES)
    const header = parseBinHeader(buf)
    expect(header.magic).toBe('DIST')
    expect(header.version).toBeGreaterThanOrEqual(1)
    expect(header.dims.length).toBeGreaterThanOrEqual(2)
    expect(header.dims[0]).toBe(header.dims[1])
  })

  it('dist.bin payload is n×n Float32 and file size matches the header', () => {
    const buf = readAsset('world', 'dist.bin')
    const { n, km } = readDistMatrix(buf)
    expect(n).toBe(loadCountriesMeta().length)
    expect(km.length).toBe(n * n)
    expect(buf.byteLength).toBe(HEADER_BYTES + n * n * BYTES_PER_VALUE)
  })

  it('distance matrix is finite, symmetric, zero-diagonal and bounded by half the circumference', () => {
    const { n, km } = readDistMatrix(readAsset('world', 'dist.bin'))
    // Geodesic max exceeds the spherical half circumference by ≤ ~0.6 %
    // (WGS84 flattening), hence the 1 % headroom on the bound.
    const maxKm = Math.PI * EARTH_RADIUS_KM * 1.01
    for (let i = 0; i < n; i++) {
      expect(km[i * n + i]).toBe(0)
      for (let j = i + 1; j < n; j++) {
        const d = km[i * n + j]
        expect(Number.isFinite(d)).toBe(true)
        expect(d).toBeGreaterThan(0)
        expect(d).toBeLessThanOrEqual(maxKm)
        expect(d).toBe(km[j * n + i])
      }
    }
  })

  it('dist.bin matches the reviewer haversine oracle on the anchored radius (N-Version, docs/12 §7a.4)', () => {
    const meta = loadCountriesMeta()
    const { n, km } = readDistMatrix(readAsset('world', 'dist.bin'))
    expect(n).toBe(meta.length)
    // Tolerance: 0.75 % relative covers sphere-vs-ellipsoid method spread
    // (≤ ~0.56 %); 5 km absolute covers centroid rounding for tiny states.
    let checked = 0
    for (let i = 0; i < n; i++) {
      const a = meta[i]
      if (a === undefined) throw new Error(`countries.meta.json has no entry ${i}`)
      for (let j = i + 1; j < n; j++) {
        const b = meta[j]
        if (b === undefined) throw new Error(`countries.meta.json has no entry ${j}`)
        const expected = haversineKm(
          degToRad(a.centroid[0]),
          degToRad(a.centroid[1]),
          degToRad(b.centroid[0]),
          degToRad(b.centroid[1]),
          EARTH_RADIUS_KM,
        )
        const actual = km[i * n + j]
        if (actual === undefined || !approxRel(actual, expected, 0.0075, 5)) {
          throw new Error(
            `dist(${a.iso3},${b.iso3}) = ${String(actual)} km, oracle ${expected} km`,
          )
        }
        checked++
      }
    }
    expect(checked).toBe((n * (n - 1)) / 2)
  })
})

describe('A-M0-4: Fixtures für Tests', () => {
  it('a committed mini binary fixture exists for the reader tests (docs/03 §Formate)', () => {
    const testFiles = listFilesRecursive(repoPath('tests'))
    const fixtures = testFiles.filter(
      (file) => /fixture/i.test(file) && (file.endsWith('.bin') || file.endsWith('.png')),
    )
    expect(fixtures.length, 'no mini fixture (*.bin/*.png) under tests/**/fixture*').toBeGreaterThan(0)
  })
})
