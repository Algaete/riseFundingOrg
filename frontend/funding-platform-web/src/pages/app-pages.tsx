import { OrganizationWorkspacePage } from '@/features/organizations/organization-pages'
import { DashboardWorkspacePage } from '@/features/dashboard/dashboard-page'
import { AccountWorkspacePage } from '@/features/account/account-page'
import { SubscriptionWorkspacePage } from '@/features/billing/billing-pages'

export function OnboardingPage() {
  return <OrganizationWorkspacePage onboarding />
}

export function DashboardPage() {
  return <DashboardWorkspacePage />
}

export function OrganizationProfilePage() {
  return <OrganizationWorkspacePage />
}

export function AccountPage() {
  return <AccountWorkspacePage />
}

export function SubscriptionPage() {
  return <SubscriptionWorkspacePage />
}
