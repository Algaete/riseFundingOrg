import { authEs } from '@/i18n/auth/es'
import { fundingCatalogEs } from '@/i18n/funding-catalog/es'
import { marketplaceEs } from '@/i18n/marketplace/es'
import { discoveryFeedbackEs } from '@/i18n/discovery-feedback/es'
import { dashboardEs } from '@/i18n/dashboard/es'
import { accountEs } from '@/i18n/account/es'
import { organizationEs } from '@/i18n/organization/es'
import { projectsEs } from '@/i18n/projects/es'
import { projectAssetsEs } from '@/i18n/project-assets/es'
import { workspaceFeedbackEs } from '@/i18n/workspace-feedback/es'

export const es = {
  translation: {
    auth: authEs,
    fundingCatalog: fundingCatalogEs,
    marketplace: marketplaceEs,
    discoveryFeedback: discoveryFeedbackEs,
    dashboard: dashboardEs,
    account: accountEs,
    organization: organizationEs,
    projects: projectsEs,
    projectAssets: projectAssetsEs,
    workspaceFeedback: workspaceFeedbackEs,
    appName: 'FundingPlatform',
    appTagline: 'Fondos que encuentran buenas causas',
    language: { label: 'Idioma' },
    navigation: {
      home: 'Inicio',
      main: 'Principal',
      application: 'Aplicación',
      mobile: 'Navegación móvil',
      overview: 'Resumen',
      opportunities: 'Oportunidades',
      availableFunding: 'Concursos disponibles',
      projects: 'Proyectos',
      plans: 'Planes',
      recommended: 'Compatibilidad',
      favorites: 'Favoritos',
      applications: 'Postulaciones',
      calendar: 'Calendario',
      alerts: 'Alertas',
      profile: 'Organización',
      administration: 'Administración',
      connections: 'Conexiones',
      projectReview: 'Revisión de proyectos',
      funds: 'Fondos',
      funders: 'Financiadores',
      imports: 'Importaciones',
      sources: 'Fuentes',
      users: 'Usuarios',
      organizations: 'Organizaciones',
      subscriptions: 'Suscripciones',
      errors: 'Errores',
      backToPlatform: 'Volver a la plataforma',
      account: 'Mi cuenta',
      subscription: 'Suscripción',
    },
    actions: {
      signIn: 'Ingresar',
      createAccount: 'Crear cuenta',
      changeTheme: 'Cambiar tema',
      workspace: 'Ir a mi espacio',
      signOut: 'Cerrar sesión',
      adminPanel: 'Panel administrativo',
      goToAdminPanel: 'Ir al panel administrativo',
      findFunding: 'Encontrar financiamiento',
      publishProject: 'Publicar mi proyecto',
      backToHome: 'Volver al inicio',
    },
    theme: { system: 'Sistema', light: 'Claro', dark: 'Oscuro' },
    layout: {
      adminWorkspace: 'Consola administrativa',
      organizationWorkspace: 'Espacio de organización',
      footer: 'FundingPlatform · Base técnica del MVP',
    },
    status: { loading: 'Cargando…', notFound: 'Página no encontrada' },
    home: {
      eyebrow: 'Proyectos que encuentran oportunidades',
      title: 'Conecta tu proyecto con el financiamiento y los aliados que necesita',
      description: 'Publica tus iniciativas, descubre fondos compatibles y organiza alianzas para avanzar desde la idea hasta la ejecución.',
      benefits: {
        projects: {
          title: 'Publica tu proyecto',
          description: 'Ordena su propósito, impacto y necesidades para presentarlo con claridad.',
        },
        funding: {
          title: 'Encuentra financiamiento',
          description: 'Explora oportunidades y entiende por qué coinciden con tu proyecto.',
        },
        partners: {
          title: 'Conecta con aliados',
          description: 'Descubre organizaciones y crea vínculos para colaborar o formar alianzas.',
        },
      },
    },
  },
} as const
