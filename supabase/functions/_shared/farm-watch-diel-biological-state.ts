import {
  FARM_WATCH_DEER_BIOLOGICAL_STATE_PRODUCT,
  FARM_WATCH_DIEL_PHOTOPERIOD_PRODUCT,
  type FarmWatchDeerAgeClass,
  type FarmWatchDeerMovementState,
  type FarmWatchDeerReproductiveState,
  type FarmWatchDeerSex,
} from './farm-watch-diel-biological-state-contract.ts'
import { applicableBiologicalStateLedgerIds } from './farm-watch-deer-relationship-registry.ts'

export function classifySolarPhase(args: {
  solarElevationDeg: number
  hourAngleDeg: number
}) {
  if (!Number.isFinite(args.solarElevationDeg) || !Number.isFinite(args.hourAngleDeg)) {
    throw new Error('solar state is not finite')
  }
  if (args.solarElevationDeg >= 0) return 'day' as const
  if (args.solarElevationDeg >= -6) {
    return args.hourAngleDeg < 0
      ? 'morning_civil_twilight' as const
      : 'evening_civil_twilight' as const
  }
  return 'night' as const
}

export function meteorologicalSeason(monthUtc: number) {
  if (!Number.isInteger(monthUtc) || monthUtc < 1 || monthUtc > 12) {
    throw new Error('month is invalid')
  }
  if (monthUtc === 12 || monthUtc <= 2) return 'winter' as const
  if (monthUtc <= 5) return 'spring' as const
  if (monthUtc <= 8) return 'summer' as const
  return 'fall' as const
}

export function regionalBreedingPhase(args: {
  date: string
  stateCode: string
  breedingStartMonth?: number | null
  breedingEndMonth?: number | null
  peakTimingLabel?: string | null
}) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(args.date)) throw new Error('date is invalid')
  const month = Number(args.date.slice(5, 7))
  const state = String(args.stateCode || '').toUpperCase()
  if (
    state !== 'KY' ||
    !Number.isInteger(args.breedingStartMonth) ||
    !Number.isInteger(args.breedingEndMonth)
  ) return 'unavailable' as const

  const start = Number(args.breedingStartMonth)
  const end = Number(args.breedingEndMonth)
  const within = start <= end
    ? month >= start && month <= end
    : month >= start || month <= end
  if (!within) return 'outside_documented_breeding_season' as const

  if (
    month === 11 &&
    String(args.peakTimingLabel || '').toLowerCase().includes('mid-november')
  ) return 'within_peak_month_context' as const

  return 'within_documented_breeding_season' as const
}

export function applicableDeerRelationshipIds(args: {
  stateCode: string
  sex: FarmWatchDeerSex
  ageClass: FarmWatchDeerAgeClass
  regionalBreedingPhase: ReturnType<typeof regionalBreedingPhase>
}) {
  return applicableBiologicalStateLedgerIds({
    stateCode: args.stateCode,
    sex: args.sex,
    ageClass: args.ageClass,
    regionalBreedingPhase: args.regionalBreedingPhase,
  })
}

export function buildDeerBiologicalState(args: {
  at: string
  stateCode: string
  sex?: FarmWatchDeerSex
  ageClass?: FarmWatchDeerAgeClass
  movementState?: FarmWatchDeerMovementState
  individualReproductiveState?: FarmWatchDeerReproductiveState
  diel: {
    solar_phase: typeof FARM_WATCH_DIEL_PHOTOPERIOD_PRODUCT.solarPhaseVocabulary[number]
    solar_elevation_deg: number
    solar_azimuth_deg: number
  }
  breedingEvidence?: {
    breeding_start_month?: number | null
    breeding_end_month?: number | null
    peak_timing_label?: string | null
    evidence_class?: string | null
    source_ids?: string[]
    ledger_ids?: string[]
  } | null
}) {
  const p = FARM_WATCH_DEER_BIOLOGICAL_STATE_PRODUCT
  const at = new Date(args.at)
  if (!Number.isFinite(at.getTime())) throw new Error('at is invalid')

  const sex = args.sex || 'unknown'
  const ageClass = args.ageClass || 'unknown'
  const movementState = args.movementState || 'unknown'
  const reproductive = args.individualReproductiveState || 'unknown'

  if (!p.sexVocabulary.includes(sex)) throw new Error('sex is invalid')
  if (!p.ageVocabulary.includes(ageClass)) throw new Error('age class is invalid')
  if (!p.movementVocabulary.includes(movementState)) throw new Error('movement state is invalid')
  if (!p.reproductiveVocabulary.includes(reproductive)) {
    throw new Error('individual reproductive state is invalid')
  }

  const date = at.toISOString().slice(0, 10)
  const regionalPhase = regionalBreedingPhase({
    date,
    stateCode: args.stateCode,
    breedingStartMonth: args.breedingEvidence?.breeding_start_month,
    breedingEndMonth: args.breedingEvidence?.breeding_end_month,
    peakTimingLabel: args.breedingEvidence?.peak_timing_label,
  })

  const ageTimingContext =
    sex !== 'female' || ageClass === 'unknown'
      ? 'not_resolved'
      : ageClass === 'juvenile'
      ? 'illinois_reference_supports_later_conception_than_yearling_adult'
      : 'illinois_reference_supports_earlier_conception_than_fawn'

  return {
    schema: p.outputSchemaVersion,
    method: p.algorithmVersion,
    species: p.species,
    at: at.toISOString(),
    sex,
    age_class: ageClass,
    movement_state: movementState,
    individual_reproductive_state: reproductive,
    season: meteorologicalSeason(at.getUTCMonth() + 1),
    diel: args.diel,
    regional_reproductive_context: {
      phase: regionalPhase,
      scope: String(args.stateCode).toUpperCase() === 'KY'
        ? 'kentucky_statewide_qualitative_v1'
        : 'unavailable',
      peak_timing_label: args.breedingEvidence?.peak_timing_label || null,
      evidence_class: args.breedingEvidence?.evidence_class || null,
      source_ids: args.breedingEvidence?.source_ids || [],
      ledger_ids: args.breedingEvidence?.ledger_ids || [],
      individual_state_inferred: false,
      interpretation_boundary:
        'Regional breeding phenology is population context only and does not establish estrus, conception, mating, pregnancy, or rut movement for an individual deer.',
    },
    age_timing_context: {
      state: ageTimingContext,
      coefficient_transfer_authorized: false,
      source_relationship_id:
        sex === 'female' && ageClass !== 'unknown' ? 'FW-D22' : null,
    },
    applicable_relationship_ids: applicableDeerRelationshipIds({
      stateCode: args.stateCode,
      sex,
      ageClass,
      regionalBreedingPhase: regionalPhase,
    }),
    state_provenance: {
      sex: sex === 'unknown' ? 'unknown' : 'explicit_scenario_input',
      age_class: ageClass === 'unknown' ? 'unknown' : 'explicit_scenario_input',
      movement_state:
        movementState === 'unknown' ? 'unknown' : 'explicit_scenario_input',
      individual_reproductive_state:
        reproductive === 'unknown' ? 'unknown' : 'explicit_scenario_input',
      diel: 'deterministic_solar_context',
      regional_reproductive_context:
        regionalPhase === 'unavailable' ? 'unavailable' : 'regional_evidence',
    },
    confidence: {
      diel: 'deterministic',
      regional_reproductive_context:
        regionalPhase === 'unavailable' ? 'unavailable' : 'regional_summary',
      individual_reproductive_state:
        reproductive === 'unknown' ? 'unknown' : 'scenario_declared',
    },
    scoring_performed: false,
    behavioral_inference_performed: false,
    interpretation_boundary:
      'Explicit deer biological scenario and regional timing context only. Unknown individual states remain unknown; no deer-use, movement-rate, habitat-quality, bedding, travel, or management score is produced.',
  }
}
