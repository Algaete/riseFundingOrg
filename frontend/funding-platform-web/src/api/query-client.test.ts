import { describe, expect, it, vi } from 'vitest'
import { ApiError } from './http-client'
import { createAppQueryClient } from './query-client'

describe('bounded database recovery', () => {
  it('does not multiply exhausted server reconnections and permits an explicit later retry', async () => {
    const client = createAppQueryClient()
    const unavailable = new ApiError({ title: 'Temporary outage', status: 503,
      type: 'https://fundingplatform.local/problems/data-service-unavailable' }, new Response(null, { status: 503 }))
    const read = vi.fn().mockRejectedValueOnce(unavailable).mockResolvedValueOnce({ totalCount: 10 })
    await expect(client.fetchQuery({ queryKey: ['resume-catalog'], queryFn: read })).rejects.toBe(unavailable)
    expect(read).toHaveBeenCalledTimes(1)
    await expect(client.fetchQuery({ queryKey: ['resume-catalog'], queryFn: read })).resolves.toEqual({ totalCount: 10 })
    expect(read).toHaveBeenCalledTimes(2)
    client.clear()
  })

  it('never automatically repeats a mutation after a service outage', async () => {
    const client = createAppQueryClient()
    const write = vi.fn().mockRejectedValue(new ApiError({ title: 'Unavailable', status: 503 }, new Response(null, { status: 503 })))
    const mutation = client.getMutationCache().build(client, { mutationFn: write })
    await expect(mutation.execute(undefined)).rejects.toBeInstanceOf(ApiError)
    expect(write).toHaveBeenCalledTimes(1)
    client.clear()
  })
})
