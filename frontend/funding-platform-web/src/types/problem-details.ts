export interface ValidationErrors {
  [field: string]: string[]
}

export interface FieldValidationIssue {
  code: string
  min?: number | null
  max?: number | null
}

export interface ProblemDetails {
  type?: string
  title: string
  status: number
  detail?: string
  instance?: string
  traceId?: string
  correlationId?: string
  errors?: ValidationErrors
  validationIssues?: Record<string, FieldValidationIssue[]>
}
