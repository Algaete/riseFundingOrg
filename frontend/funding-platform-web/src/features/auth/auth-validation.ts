import { z } from 'zod'
import type { authEs } from '@/i18n/auth/es'

export type AuthValidationKey = `auth.validation.${keyof typeof authEs.validation}`
const message = (key: AuthValidationKey) => key

// Store message keys, not translated strings: visible errors change language
// without resetting form values or repeating an authentication request.
const passwordSchema = z.string()
  .min(12, message('auth.validation.passwordMin'))
  .max(128, message('auth.validation.passwordMax'))
const email = z.string().email(message('auth.validation.emailInvalid')).max(320, message('auth.validation.emailMax'))

export const loginSchema = z.object({
  email: z.string().min(1, message('auth.validation.emailRequired')).email(message('auth.validation.emailInvalid')),
  password: z.string().min(1, message('auth.validation.passwordRequired')).max(128, message('auth.validation.passwordMax')),
})
export const registerSchema = z.object({
  displayName: z.string().trim().min(1, message('auth.validation.nameRequired')).max(150, message('auth.validation.nameMax')),
  email,
  password: passwordSchema,
  confirmPassword: z.string(),
}).refine(values => values.password === values.confirmPassword, {
  message: message('auth.validation.passwordMatch'), path: ['confirmPassword'],
})
export const emailSchema = z.object({ email })
export const resetSchema = z.object({ password: passwordSchema, confirmPassword: z.string() })
  .refine(values => values.password === values.confirmPassword, {
    message: message('auth.validation.passwordMatch'), path: ['confirmPassword'],
  })
export const codeSchema = z.object({
  code: z.string().trim().min(6, message('auth.validation.codeRequired')).max(64, message('auth.validation.codeMax')),
})
export const mfaSetupCodeSchema = z.object({
  code: z.string().trim().regex(/^\d{6}$/, message('auth.validation.setupCode')),
})
