import {
  HRRR_LAMBERT_CONE,
  HRRR_REQUIRED_FIELDS,
  candidateReferenceTimes,
  findAnalysisRecord,
  hrrrAnalysisFileUrl,
  hrrrAnalysisIndexUrl,
  selectRequiredAnalysisRecords,
  rotateHrrrGridWind,
} from './farm-watch-hrrr.ts'

function assert(condition: unknown, message = 'assertion failed'): asserts condition {
  if (!condition) throw new Error(message)
}

function approx(actual: number, expected: number, tolerance: number) {
  assert(Math.abs(actual - expected) <= tolerance, `${actual} not within ${tolerance} of ${expected}`)
}

Deno.test('HRRR candidate reference times floor to UTC hour and walk backward', () => {
  const values = candidateReferenceTimes(new Date('2026-09-21T17:42:31Z'), 3)
  assert(values.map((value) => value.toISOString()).join(',') === [
    '2026-09-21T17:00:00.000Z',
    '2026-09-21T16:00:00.000Z',
    '2026-09-21T15:00:00.000Z',
    '2026-09-21T14:00:00.000Z',
  ].join(','))
})

Deno.test('HRRR f00 analysis URL is deterministic', () => {
  const time = new Date('2026-09-21T12:00:00Z')
  assert(
    hrrrAnalysisFileUrl(time) ===
      'https://noaa-hrrr-bdp-pds.s3.amazonaws.com/hrrr.20260921/conus/hrrr.t12z.wrfsfcf00.grib2',
  )
  assert(hrrrAnalysisIndexUrl(time) === hrrrAnalysisFileUrl(time) + '.idx')
})

Deno.test('HRRR tangent Lambert cone matches sin 38.5 degrees', () => {
  approx(HRRR_LAMBERT_CONE, Math.sin(38.5 * Math.PI / 180), 1e-12)
})

Deno.test('analysis record selection accepts NCEP anl token', () => {
  const idx = [
    '1:0:d=2026092112:TMP:2 m above ground:anl:',
    '2:100:d=2026092112:DPT:2 m above ground:anl:',
    '3:200:d=2026092112:RH:2 m above ground:anl:',
    '4:300:d=2026092112:UGRD:10 m above ground:anl:',
    '5:400:d=2026092112:VGRD:10 m above ground:anl:',
    '6:500:d=2026092112:DSWRF:surface:anl:',
    '7:600:d=2026092112:DLWRF:surface:anl:',
    '8:700:d=2026092112:TCDC:entire atmosphere:anl:',
    '9:800:d=2026092112:PRATE:surface:anl:',
    '10:900:d=2026092112:HGT:surface:anl:',
  ].join('\n')
  const selected = selectRequiredAnalysisRecords(idx)
  assert(selected.air_temperature_2m_c.offset === 0)
  assert(selected.precipitation_rate_mm_hr.offset === 800)
  assert(selected.air_temperature_2m_c.length === 100)
})

Deno.test('analysis selector rejects a forecast-only record', () => {
  let threw = false
  try {
    findAnalysisRecord([
      { variable: 'TMP', level: '2 m above ground', forecast: '1 hour fcst', offset: 0, length: 100 },
    ], 'TMP', '2 m above ground')
  } catch {
    threw = true
  }
  assert(threw)
})

Deno.test('HRRR candidate reference times cross the UTC date boundary correctly', () => {
  const values = candidateReferenceTimes(new Date('2026-09-21T01:12:00Z'), 3)
  assert(values[0]!.toISOString() === '2026-09-21T01:00:00.000Z')
  assert(values[2]!.toISOString() === '2026-09-20T23:00:00.000Z')
  assert(
    hrrrAnalysisFileUrl(values[2]!) ===
      'https://noaa-hrrr-bdp-pds.s3.amazonaws.com/hrrr.20260920/conus/hrrr.t23z.wrfsfcf00.grib2',
  )
})

Deno.test('HRRR field conversions preserve documented units', () => {
  const byKey = Object.fromEntries(HRRR_REQUIRED_FIELDS.map((field) => [field.key, field]))
  approx(byKey.air_temperature_2m_c.convert(300), 26.85, 1e-12)
  approx(byKey.dew_point_2m_c.convert(280), 6.85, 1e-12)
  approx(byKey.precipitation_rate_mm_hr.convert(0.001), 3.6, 1e-12)
  approx(byKey.downward_shortwave_wm2.convert(725), 725, 0)
  approx(byKey.downward_longwave_wm2.convert(340), 340, 0)
})

Deno.test('HRRR Lambert wind rotation preserves speed and true direction at orientation longitude', () => {
  const wind = rotateHrrrGridWind(3, 4, 262.5)
  approx(wind.speedMps, 5, 1e-12)
  approx(wind.uEastMps, 3, 1e-12)
  approx(wind.vNorthMps, 4, 1e-12)
  approx(wind.directionFromDeg, 216.86989764584402, 1e-9)
})

Deno.test('HRRR Lambert wind rotation changes orientation away from central meridian without changing speed', () => {
  const wind = rotateHrrrGridWind(3, 4, 275)
  approx(wind.speedMps, 5, 1e-12)
  assert(Math.abs(wind.uEastMps - 3) > 0.01)
  assert(wind.directionFromDeg >= 0 && wind.directionFromDeg < 360)
})
