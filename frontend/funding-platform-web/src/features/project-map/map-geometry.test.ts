import { describe, expect, it } from 'vitest'
import { clusterPoints, projectPoint, viewport } from './map-geometry'
import { mapQuery, type MapPoint } from './project-map-api'

const point = (id: string, latitude = -33.46, longitude = -70.65): MapPoint => ({ publicId: id, slug: id, title: id, summary: null, organizationName: 'ONG', latitude, longitude, projectStatus: 2, projectStage: 0, fundingGap: 100, currency: 'USD' })
describe('public project map', () => {
  it('projects equator and world boundaries without changing source data', () => {
    expect(projectPoint(point('a', 0, 0))).toEqual({ x: 360, y: 180 })
    expect(projectPoint(point('a', 90, -180))).toEqual({ x: 0, y: 0 })
    expect(projectPoint(point('a', -90, 180))).toEqual({ x: 720, y: 360 })
  })
  it('bounds zoom and pan to the world', () => {
    expect(viewport(-2)).toEqual({ x: 0, y: 0, width: 720, height: 360 })
    expect(viewport(9, { x: -1000, y: -1000 })).toEqual({ x: 0, y: 0, width: 22.5, height: 11.25 })
    const box = viewport(5, { x: 1000, y: 1000 })
    expect(box.x + box.width).toBe(720); expect(box.y + box.height).toBe(360)
  })
  it('groups nearby projects and separates distant ones', () => {
    const clusters = clusterPoints([point('a'), point('b'), point('c', 40, 10)], 0)
    expect(clusters.map(c => c.items.length).sort()).toEqual([1, 2])
    expect(clusters.flatMap(c => c.items.map(p => p.publicId)).sort()).toEqual(['a', 'b', 'c'])
  })
  it('does not plot invalid or missing coordinates', () => {
    expect(clusterPoints([point('a', NaN), point('b', 91), point('c', 0, Infinity), point('d', 0, -181)], 0)).toEqual([])
  })
  it('normalizes known filters preserving stage and status zero', () => {
    const query = mapQuery(new URLSearchParams('q=%20agua%20&projectStage=0&projectStatus=0&countryId=152&categoryId=1&sustainableDevelopmentGoalId=17&page=2&pageSize=900&private=true'))
    expect(Object.fromEntries(query)).toEqual({ q: 'agua', countryId: '152', categoryId: '1', projectStage: '0', sustainableDevelopmentGoalId: '17', projectStatus: '0', page: '2', pageSize: '100' })
  })
  it('drops invalid filters and bounds search text', () => {
    const query = mapQuery(new URLSearchParams(`q=${'a'.repeat(201)}&projectStage=6&projectStatus=7&countryId=-1&categoryId=1.2&sustainableDevelopmentGoalId=18&page=10001`))
    expect([...query.keys()]).toEqual(['q', 'page', 'pageSize']); expect(query.get('q')).toHaveLength(200)
    expect(query.get('page')).toBe('1')
  })
})
