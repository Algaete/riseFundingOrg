import type { catalogsEs } from './es'
import type { TranslationShape } from '@/i18n/resource-types'

export const catalogsEn = {
  "countries": {
    "CL": {
      "current": "Chile"
    }
  },
  "regions": {},
  "currencies": {
    "CLP": {
      "current": "Chilean peso"
    },
    "USD": {
      "current": "US dollar"
    },
    "EUR": {
      "current": "Euro"
    }
  },
  "fundingCategories": {
    "ENVIRONMENT": {
      "legacy": "Environment",
      "current": "Environment and biodiversity"
    },
    "EDUCATION": {
      "current": "Education"
    },
    "SOCIAL_DEVELOPMENT": {
      "legacy": "Social development",
      "current": "Social development and poverty reduction"
    },
    "HEALTH": {
      "current": "Health"
    },
    "CULTURE": {
      "current": "Culture and heritage"
    },
    "HUMAN_RIGHTS": {
      "legacy": "Human rights",
      "current": "Human rights, democracy and governance"
    },
    "ECONOMIC_DEVELOPMENT": {
      "legacy": "Local economic development",
      "current": "Economic development, employment and entrepreneurship"
    },
    "INNOVATION": {
      "legacy": "Innovation and technology",
      "current": "Innovation, science and technology"
    },
    "CLIMATE_CHANGE": {
      "current": "Climate change"
    },
    "WATER_SANITATION": {
      "current": "Water and sanitation"
    },
    "AGRICULTURE_FOOD_SECURITY": {
      "current": "Agriculture and food security"
    },
    "GENDER_EQUALITY": {
      "current": "Gender and equality"
    },
    "PEACE_CONFLICT_HUMANITARIAN": {
      "current": "Peace, conflict and humanitarian aid"
    },
    "CITIES_HOUSING_TERRITORIAL": {
      "current": "Cities, housing and territorial development"
    },
    "SPORT_COMMUNITY_DEVELOPMENT": {
      "current": "Sport and community development"
    },
    "OTHER": {
      "current": "Other"
    }
  },
  "organizationTypes": {
    "NGO": {
      "current": "Non-governmental organization"
    },
    "FOUNDATION": {
      "current": "Foundation"
    },
    "CORPORATION": {
      "current": "Corporation"
    },
    "COMMUNITY_ORGANIZATION": {
      "current": "Community organization"
    },
    "OTHER_NONPROFIT": {
      "current": "Other nonprofit organization"
    }
  },
  "legalEntityTypes": {
    "CL_FOUNDATION": {
      "current": "Foundation"
    },
    "CL_CORPORATION": {
      "current": "Corporation"
    },
    "CL_COMMUNITY_ORGANIZATION": {
      "current": "Functional or territorial community organization"
    },
    "CL_OTHER_NONPROFIT": {
      "current": "Other nonprofit legal entity"
    }
  },
  "organizationSizes": {
    "MICRO": {
      "current": "Micro"
    },
    "SMALL": {
      "current": "Small"
    },
    "MEDIUM": {
      "current": "Medium"
    },
    "LARGE": {
      "current": "Large"
    },
    "EMPLOYEES_1_10": {
      "current": "1–10 people"
    },
    "EMPLOYEES_11_50": {
      "current": "11–50 people"
    },
    "EMPLOYEES_51_100": {
      "current": "51–100 people"
    },
    "EMPLOYEES_101_PLUS": {
      "current": "101+ people"
    }
  },
  "beneficiaryTypes": {
    "CHILDREN": {
      "current": "Children and adolescents"
    },
    "YOUTH": {
      "current": "Young people"
    },
    "OLDER_ADULTS": {
      "current": "Older adults"
    },
    "WOMEN": {
      "current": "Women"
    },
    "PEOPLE_WITH_DISABILITIES": {
      "current": "People with disabilities"
    },
    "INDIGENOUS_PEOPLES": {
      "current": "Indigenous peoples"
    },
    "MIGRANTS": {
      "current": "Migrants and refugees"
    },
    "COMMUNITIES": {
      "current": "Communities and territorial organizations"
    },
    "RURAL_COMMUNITIES": {
      "current": "Rural communities"
    },
    "PEOPLE_IN_POVERTY_OR_VULNERABILITY": {
      "current": "People experiencing poverty or vulnerability"
    },
    "ENTREPRENEURS_AND_SMALL_PRODUCERS": {
      "current": "Entrepreneurs and small producers"
    },
    "OTHER": {
      "current": "Other"
    }
  },
  "projectTypes": {
    "PROGRAM": {
      "current": "Program"
    },
    "RESEARCH": {
      "current": "Research"
    },
    "INFRASTRUCTURE": {
      "current": "Infrastructure"
    },
    "CAPACITY_BUILDING": {
      "current": "Institutional strengthening"
    },
    "ADVOCACY": {
      "legacy": "Advocacy",
      "current": "Advocacy and public policy"
    },
    "EMERGENCY_RESPONSE": {
      "legacy": "Emergency response",
      "current": "Humanitarian aid and emergency response"
    },
    "COMMUNITY_DEVELOPMENT": {
      "current": "Community development"
    },
    "TRAINING_CAPACITY_DEVELOPMENT": {
      "current": "Training and capacity development"
    },
    "INNOVATION_TECHNOLOGY": {
      "current": "Innovation and technology"
    },
    "ENTREPRENEURSHIP_PRODUCTIVE_DEVELOPMENT": {
      "current": "Entrepreneurship and productive development"
    },
    "ENVIRONMENTAL_CONSERVATION_RESTORATION": {
      "current": "Environmental conservation and restoration"
    },
    "DISASTER_RISK_PREVENTION_REDUCTION": {
      "current": "Disaster risk prevention and reduction"
    },
    "OTHER": {
      "current": "Other"
    }
  },
  "fundingTypes": {
    "GRANT": {
      "current": "Grant"
    },
    "AWARD": {
      "current": "Award"
    },
    "FELLOWSHIP": {
      "current": "Fellowship"
    },
    "TECHNICAL_ASSISTANCE": {
      "current": "Technical assistance"
    },
    "IN_KIND": {
      "current": "In-kind contribution"
    }
  },
  "languages": {
    "es": {
      "current": "Spanish"
    },
    "en": {
      "current": "English"
    },
    "pt": {
      "current": "Portuguese"
    },
    "fr": {
      "current": "French"
    },
    "und": {
      "current": "Other"
    }
  },
  "sustainableDevelopmentGoals": {
    "SDG_01": {
      "current": "No Poverty"
    },
    "SDG_02": {
      "current": "Zero Hunger"
    },
    "SDG_03": {
      "current": "Good Health and Well-being"
    },
    "SDG_04": {
      "current": "Quality Education"
    },
    "SDG_05": {
      "current": "Gender Equality"
    },
    "SDG_06": {
      "current": "Clean Water and Sanitation"
    },
    "SDG_07": {
      "current": "Affordable and Clean Energy"
    },
    "SDG_08": {
      "current": "Decent Work and Economic Growth"
    },
    "SDG_09": {
      "current": "Industry, Innovation and Infrastructure"
    },
    "SDG_10": {
      "current": "Reduced Inequalities"
    },
    "SDG_11": {
      "current": "Sustainable Cities and Communities"
    },
    "SDG_12": {
      "current": "Responsible Consumption and Production"
    },
    "SDG_13": {
      "current": "Climate Action"
    },
    "SDG_14": {
      "current": "Life Below Water"
    },
    "SDG_15": {
      "current": "Life on Land"
    },
    "SDG_16": {
      "current": "Peace, Justice and Strong Institutions"
    },
    "SDG_17": {
      "current": "Partnerships for the Goals"
    }
  },
  "fundingExperienceTypes": {
    "GOVERNMENTS_PUBLIC_FUNDS": {
      "current": "Governments / public funds"
    },
    "FOUNDATIONS_GRANTMAKERS": {
      "current": "Foundations / grantmakers"
    },
    "MULTILATERAL_ORGANIZATIONS": {
      "current": "Multilateral organizations"
    },
    "INTERNATIONAL_COOPERATION": {
      "current": "International cooperation"
    },
    "COMPANIES": {
      "current": "Companies"
    },
    "PHILANTHROPISTS": {
      "current": "Philanthropists"
    }
  },
  "tags": {}
} satisfies TranslationShape<typeof catalogsEs>
