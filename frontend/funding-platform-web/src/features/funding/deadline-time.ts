// Convert an editor's wall-clock time using the selected IANA zone, never the
// browser's zone. Round-trip candidate offsets so DST gaps/folds fail explicitly.
export function dateTimeInZone(instant: string, timeZone: string): string | null {
  const date = new Date(instant)
  if (!Number.isFinite(date.getTime())) return null
  try {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone, calendar: 'gregory', numberingSystem: 'latn', hourCycle: 'h23',
      year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
    }).formatToParts(date)
    const part = (type: Intl.DateTimeFormatPartTypes) => parts.find(value => value.type === type)?.value
    return `${part('year')}-${part('month')}-${part('day')}T${part('hour')}:${part('minute')}`
  } catch { return null }
}

export type DeadlineResolution = { utc: string; error?: never } | {
  utc?: never; error: 'invalid' | 'zone' | 'nonexistent' | 'ambiguous'
}

export function resolveDeadline(local: string, zone: string): DeadlineResolution {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(local)) return { error: 'invalid' }
  const nominal = new Date(`${local}:00Z`)
  if (!Number.isFinite(nominal.getTime()) || nominal.toISOString().slice(0, 16) !== local) return { error: 'invalid' }
  const offsets = new Set<number>()
  // Both sides of a transition, including non-hour offsets and date-line shifts.
  for (let hours = -48; hours <= 48; hours += 6) {
    const probe = nominal.getTime() + hours * 3_600_000
    const wall = dateTimeInZone(new Date(probe).toISOString(), zone)
    if (!wall) return { error: 'zone' }
    offsets.add(new Date(`${wall}:00Z`).getTime() - probe)
  }
  const matches = [...offsets].map(offset => new Date(nominal.getTime() - offset).toISOString())
    .filter(instant => dateTimeInZone(instant, zone) === local)
  if (matches.length === 0) return { error: 'nonexistent' }
  if (matches.length !== 1) return { error: 'ambiguous' }
  return { utc: matches[0] }
}

export function availableTimeZones(current = ''): string[] {
  const fallback = ['America/Santiago', 'America/Punta_Arenas', 'Pacific/Easter', 'America/Lima', 'America/Bogota', 'America/New_York', 'Europe/Madrid']
  const zones = typeof Intl.supportedValuesOf === 'function' ? Intl.supportedValuesOf('timeZone') : fallback
  return [...new Set(['UTC', ...fallback, ...zones, ...(current ? [current] : [])])].sort()
}
