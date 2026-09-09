import type { TranslationShape } from '@/i18n/resource-types'
import type { calendarEs } from './es'

export const calendarEn = {
  "organizationHelp": "The calendar brings together dates from your organization’s projects, applications and favorites.",
  "allDay": "All day",
  "approximate": " · Approximate date",
  "loading": "Loading calendar…",
  "eyebrow": "Organization schedule",
  "title": "Calendar",
  "help": "Deadlines and milestones recorded for {{name}}. Always confirm dates with the opportunity’s official source.",
  "month": "Calendar month",
  "previousMonth": "Previous month",
  "nextMonth": "Next month",
  "count_one": "{{count}} event this month",
  "count_other": "{{count}} events this month",
  "preparing": "Preparing events…",
  "loadingEvents": "Loading milestones…",
  "loadFailed": "We could not load the calendar",
  "empty": "No milestones this month",
  "emptyHelp": "Check another month or add dates to your projects and applications.",
  "viewApplications": "View applications",
  "viewProjects": "View projects",
  "eventTypes": {
    "application-deadline": "Application opportunity deadline",
    "planned-submission": "Planned submission",
    "application-result": "Expected result",
    "project-start": "Project start",
    "project-end": "Project end",
    "favorite-deadline": "Favorite opportunity deadline"
  }
} satisfies TranslationShape<typeof calendarEs>
