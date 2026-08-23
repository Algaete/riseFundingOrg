export interface ValidationErrors {
  [field: string]: string[]
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
}
