import { availableTimeZones, dateTimeInZone, resolveDeadline } from './deadline-time'

describe('editorial deadlines in the selected time zone', () => {
  it.each([
    ['2027-01-31T23:59', 'America/Santiago', '2027-02-01T02:59:00.000Z'],
    ['2026-07-15T12:30', 'America/Santiago', '2026-07-15T16:30:00.000Z'],
    ['2026-07-15T12:30', 'Asia/Kathmandu', '2026-07-15T06:45:00.000Z'],
    ['2026-07-15T00:00', 'Pacific/Kiritimati', '2026-07-14T10:00:00.000Z'],
    ['2026-07-15T12:30', 'UTC', '2026-07-15T12:30:00.000Z'],
  ])('converts %s in %s without using the host time zone', (local, zone, utc) => {
    expect(resolveDeadline(local, zone)).toEqual({ utc })
    expect(dateTimeInZone(utc, zone)).toBe(local)
  })
  it.each([
    ['2026-03-08T02:30', 'America/New_York', 'nonexistent'],
    ['2026-11-01T01:30', 'America/New_York', 'ambiguous'],
    ['2026-02-30T12:30', 'UTC', 'invalid'],
    ['2026-07-15T12:30:00', 'UTC', 'invalid'],
    ['2026-07-15T12:30', 'Santiago de Chile', 'zone'],
  ])('rejects %s in %s explicitly', (local, zone, error) => {
    expect(resolveDeadline(local, zone)).toEqual({ error })
  })
  it('offers known zones and preserves an existing zone alias', () => {
    expect(availableTimeZones('US/Eastern')).toEqual(expect.arrayContaining(['UTC', 'America/Santiago', 'US/Eastern']))
  })
})
