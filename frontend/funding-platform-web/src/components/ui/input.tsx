import { forwardRef, type InputHTMLAttributes } from 'react'

import { cn } from '@/utils/cn'

export const Input = forwardRef<
  HTMLInputElement,
  InputHTMLAttributes<HTMLInputElement>
>(({ className, ...props }, ref) => (
  <input
    ref={ref}
    className={cn(
      'flex h-10 w-full rounded-lg border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground disabled:opacity-50',
      className,
    )}
    {...props}
  />
))

Input.displayName = 'Input'
