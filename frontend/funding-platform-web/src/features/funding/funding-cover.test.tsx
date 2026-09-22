import { fireEvent, render, screen } from '@testing-library/react'
import { vi } from 'vitest'
import { language } from '@/test/tracking-test-harness'
import { FundingCover } from './funding-cover'
import { FundingCoverPicker } from './funding-cover-picker'
import { fundingCoverKeys, isFundingCoverKey, resolveFundingCover } from './funding-covers'

describe('funding cover library', () => {
  it.each(fundingCoverKeys)('resolves %s to a bundled asset', key => {
    expect(isFundingCoverKey(key)).toBe(true)
    expect(resolveFundingCover(key).src).toMatch(/^\/images\/funding-covers\/[a-z]+-v1\.jpg$/)
  })

  it.each([null, undefined, '', '../secret', 'https://example.invalid/image.jpg', 'data:image/svg+xml,abc', '__proto__', 'constructor', 'future-v2'])('uses the safe default for %s without creating a URL from input', key => {
    expect(resolveFundingCover(key)).toEqual(resolveFundingCover('community-v1'))
    expect(isFundingCoverKey(key ?? '')).toBe(false)
  })

  it('keeps the editorial image when changing language and labels it as an illustration', async () => {
    const { container } = render(<FundingCover coverKey="nature-v1" />)
    expect(screen.getByRole('img', { name: 'Ilustración temática de portada: Naturaleza y ambiente' })).toBeInTheDocument()
    expect(screen.getByText('Ilustración temática · IA')).toBeInTheDocument()
    expect(container.querySelector('img')).toHaveAttribute('src', '/images/funding-covers/nature-v1.jpg')
    expect(container.querySelector('img')).toHaveAttribute('loading', 'lazy')
    expect(container.querySelector('img')).toHaveAttribute('width', '1200')
    await language('en')
    expect(screen.getByRole('img', { name: 'Thematic cover illustration: Nature and environment' })).toBeInTheDocument()
    expect(container.querySelector('img')).toHaveAttribute('src', '/images/funding-covers/nature-v1.jpg')
    expect(screen.getByText('Thematic illustration · AI')).toBeInTheDocument()
  })

  it('shows a safe fallback if the file fails and recovers after choosing another cover', () => {
    const { container, rerender } = render(<FundingCover coverKey="nature-v1" detail />)
    expect(container.querySelector('img')).toHaveAttribute('loading', 'eager')
    fireEvent.error(container.querySelector('img')!)
    expect(container.querySelector('img')).toBeNull()
    expect(screen.getByRole('img')).toBeInTheDocument()
    expect(screen.getByText('Ilustración temática · IA')).toBeInTheDocument()
    rerender(<FundingCover coverKey="education-v1" detail />)
    expect(container.querySelector('img')).toHaveAttribute('src', '/images/funding-covers/education-v1.jpg')
  })

  it('provides accessible selection without uploads or remote links and preserves keys across locales', async () => {
    const onChange = vi.fn()
    render(<FundingCoverPicker value="education-v1" onChange={onChange} />)
    expect(screen.getAllByRole('radio')).toHaveLength(5)
    expect(screen.getByRole('radio', { name: 'Educación y aprendizaje' })).toBeChecked()
    fireEvent.click(screen.getByRole('radio', { name: 'Ciencia e innovación' }))
    expect(onChange).toHaveBeenCalledWith('research-v1')
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    await language('en')
    expect(screen.getByRole('radio', { name: 'Education and learning' })).toBeChecked()
    expect(onChange).toHaveBeenCalledTimes(1)
  })

  it('inherits the editorial read-only lock and associates field validation with all options', () => {
    render(<fieldset disabled><FundingCoverPicker value="auto" onChange={vi.fn()} error="Confirma la portada." /></fieldset>)
    for (const radio of screen.getAllByRole('radio')) {
      expect(radio).toBeDisabled()
      expect(radio).toHaveAttribute('aria-invalid', 'true')
      expect(radio).toHaveAccessibleDescription('Confirma la portada.')
    }
    expect(screen.getByRole('alert')).toHaveTextContent('Confirma la portada.')
  })
})
