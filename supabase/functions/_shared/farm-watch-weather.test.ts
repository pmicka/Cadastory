import { createFarmWatchWeatherReader } from './farm-watch-weather.ts'
function assert(value: unknown, message = 'assertion failed'): asserts value {
  if (!value) throw new Error(message)
}
const at = Date.parse('2026-11-13T16:30:00Z')
const center = { lat: 38.2, lon: -84.9 }
function fixture({ fail = '', old = false, invalidUrl = false, missingTemperature = false } = {}) {
  let clock = at
  const calls: string[] = []
  const read = createFarmWatchWeatherReader({ now: () => clock, fetchImpl: async (input, init) => {
    const url = String(input); calls.push(url)
    assert(((init as any)?.headers)['User-Agent'].includes('FarmWatch'))
    assert((init as any)?.redirect === 'error')
    if (url.includes(fail) && fail) return new Response(null, { status: 503 })
    if (url.includes('/points/')) return Response.json({ properties: {
      timeZone: 'America/New_York', forecast: invalidUrl ? 'https://evil.test/forecast' : 'https://api.weather.gov/gridpoints/LMK/1,1/forecast',
      forecastHourly: 'https://api.weather.gov/gridpoints/LMK/1,1/forecast/hourly',
    } })
    return Response.json({ properties: { updateTime: old ? '2025-01-01T00:00:00Z' : '2026-11-13T15:00:00Z', periods: [{
      name: 'Today', startTime: '2026-11-13T16:00:00Z', endTime: '2026-11-13T17:00:00Z',
      temperature: missingTemperature ? null : 54, temperatureUnit: 'F', isDaytime: true,
      shortForecast: 'Partly Sunny', windSpeed: '5 mph', windDirection: 'NW', probabilityOfPrecipitation: { value: null },
    }] } })
  } })
  return { read, calls, advance(ms: number) { clock += ms } }
}
Deno.test('weather uses authorized stored-center point forecast with compact provenance', async () => {
  const f = fixture()
  const value = await f.read(center)
  assert(value.status === 'available')
  assert(value.current.temperature === 54 && value.current.precipitation_percent === null)
  assert(value.kind === 'forecast' && value.source === 'National Weather Service')
  assert(Date.parse(value.expires_at) <= at + 15 * 60 * 1000)
  assert(f.calls.length === 3)
  assert(JSON.stringify(value).length < 2000)
})
Deno.test('weather deduplicates concurrent calls and bounds cache reuse', async () => {
  const f = fixture()
  await Promise.all([f.read(center), f.read(center)])
  await f.read(center)
  assert(f.calls.length === 3)
  f.advance(16 * 60 * 1000)
  await f.read(center)
  assert(Number(f.calls.length) === 6)
})
Deno.test('weather isolates forecast branches and rejects provider URL redirects', async () => {
  for (const options of [{ fail: '/hourly' }, { invalidUrl: true }]) {
    const f = fixture(options)
    const value = await f.read(center)
    assert(value.status === 'partial')
    assert(f.calls.every(url => url.startsWith('https://api.weather.gov/')))
    await f.read(center)
    assert(f.calls.filter(url => url.includes('/points/')).length === 2, 'partial failures must allow a targeted retry')
  }
})
Deno.test('old, missing, and failed weather never become current or synthetic zeroes', async () => {
  for (const options of [{ fail: '/points/' }, { old: true }, { missingTemperature: true }]) {
    const value = await fixture(options).read(center)
    assert(value.status === 'unavailable' && value.current === null && !value.periods.length)
  }
  const f = fixture()
  assert((await f.read(null)).status === 'unavailable' && f.calls.length === 0)
})
Deno.test('weather deadline includes upstream requests and fails locally', async () => {
  const read = createFarmWatchWeatherReader({ timeoutMs: 5, fetchImpl: (_url, init) =>
    new Promise((_resolve, reject) => (init as any)?.signal?.addEventListener('abort', () => reject(new Error('timeout')))) })
  assert((await read(center)).status === 'unavailable')
})
