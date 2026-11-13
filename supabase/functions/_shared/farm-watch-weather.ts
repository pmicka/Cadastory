// Everyday point forecasts only. This feed does not enter scientific evidence,
// freshness identities, materializations, or deer interpretation.
const API = 'https://api.weather.gov'
const MAX_AGE_MS = 12 * 60 * 60 * 1000
const CACHE_MS = 15 * 60 * 1000

function forecastUrl(value: unknown) {
  if (typeof value !== 'string') throw new Error('Forecast URL unavailable')
  const url = new URL(value)
  if (url.origin !== API || !url.pathname.startsWith('/gridpoints/') || url.username || url.password) {
    throw new Error('Invalid forecast authority')
  }
  return url.href
}

function period(value: any, now: number) {
  const start = Date.parse(value?.startTime)
  const end = Date.parse(value?.endTime)
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= now || end <= start ||
      !Number.isFinite(value?.temperature) || !['F', 'C'].includes(value.temperatureUnit) ||
      typeof value.shortForecast !== 'string') return null
  const precipitation = value.probabilityOfPrecipitation?.value
  return {
    name: String(value.name || '').slice(0, 50), start_at: new Date(start).toISOString(),
    end_at: new Date(end).toISOString(), is_daytime: value.isDaytime === true,
    temperature: value.temperature, temperature_unit: value.temperatureUnit,
    description: value.shortForecast.slice(0, 160),
    wind_speed: typeof value.windSpeed === 'string' ? value.windSpeed.slice(0, 40) : null,
    wind_direction: typeof value.windDirection === 'string' ? value.windDirection.slice(0, 8) : null,
    precipitation_percent: typeof precipitation === 'number' && precipitation >= 0 && precipitation <= 100
      ? precipitation : null,
  }
}

function projection(payload: any, now: number) {
  const props = payload?.properties
  const updated = Date.parse(props?.updateTime || props?.updated || props?.generatedAt)
  if (!Number.isFinite(updated) || updated > now + 5 * 60 * 1000 || now - updated > MAX_AGE_MS) return null
  const periods = Array.isArray(props?.periods)
    ? props.periods.map((p: any) => period(p, now)).filter(Boolean) : []
  return { updated_at: new Date(updated).toISOString(), periods }
}

export function createFarmWatchWeatherReader({ fetchImpl = fetch, now = Date.now, timeoutMs = 8000 } = {}) {
  const cache = new Map<string, { until: number; value: any }>()
  const inflight = new Map<string, Promise<any>>()
  return async function readWeather(center: { lat: number; lon: number } | null) {
    const unavailable = { status: 'unavailable', source: 'National Weather Service', current: null, periods: [] }
    if (!center || !Number.isFinite(center.lat) || !Number.isFinite(center.lon) ||
        Math.abs(center.lat) > 90 || Math.abs(center.lon) > 180) return unavailable
    const key = `${center.lat.toFixed(4)},${center.lon.toFixed(4)}`
    const stored = cache.get(key)
    if (stored && stored.until > now()) return stored.value
    if (inflight.has(key)) return inflight.get(key)
    const operation = (async () => {
      const controller = new AbortController()
      const timer = setTimeout(() => controller.abort(), timeoutMs)
      async function read(url: string) {
        const response = await fetchImpl(url, { signal: controller.signal, redirect: 'error', headers: {
          'User-Agent': 'FarmWatch/1.0 (+https://pmicka.com)', Accept: 'application/geo+json',
        } })
        if (!response.ok) throw new Error('Weather source unavailable')
        return await response.json()
      }
      try {
        const point = await read(`${API}/points/${key}`)
        const urls = point?.properties
        const results = await Promise.allSettled([
          Promise.resolve().then(() => read(forecastUrl(urls?.forecastHourly))),
          Promise.resolve().then(() => read(forecastUrl(urls?.forecast))),
        ])
        const at = now()
        const hourly = results[0].status === 'fulfilled' ? projection(results[0].value, at) : null
        const daily = results[1].status === 'fulfilled' ? projection(results[1].value, at) : null
        const current = hourly?.periods.find((p: any) => Date.parse(p.start_at) <= at) || null
        const periods = daily?.periods.slice(0, 6) || []
        if (!current && !periods.length) return unavailable
        const updated = [current && hourly?.updated_at, periods.length && daily?.updated_at]
          .filter(Boolean).map(String).sort()[0]
        let timeZone = 'UTC'
        try { new Intl.DateTimeFormat('en-US', { timeZone: urls?.timeZone }).format(at); timeZone = urls?.timeZone || 'UTC' } catch { /* Explicit UTC fallback. */ }
        const until = Math.min(at + CACHE_MS, Date.parse(updated) + MAX_AGE_MS,
          current ? Date.parse(current.end_at) : Infinity,
          ...periods.map((p: any) => Date.parse(p.end_at)))
        const value = { status: current && periods.length ? 'available' : 'partial',
          source: 'National Weather Service', kind: 'forecast', time_zone: timeZone,
          updated_at: updated, retrieved_at: new Date(at).toISOString(),
          expires_at: new Date(until).toISOString(), current, periods }
        if (cache.size >= 20) cache.delete(cache.keys().next().value!)
        if (value.status === 'available') cache.set(key, { until, value })
        return value
      } catch { return unavailable } finally { clearTimeout(timer) }
    })()
    inflight.set(key, operation)
    try { return await operation } finally { inflight.delete(key) }
  }
}
