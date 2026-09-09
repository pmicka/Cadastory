import {
  buildComponentSandboxHtml as buildComponentSandboxHtmlV18,
  type SandboxMapMember,
  type SandboxMapTarget as SandboxMapTargetV18,
  type SandboxMapTerritory,
  type SandboxContactCard,
  type SandboxContactRoute,
} from './component_v18.ts'

export type { SandboxMapMember, SandboxMapTerritory, SandboxContactCard, SandboxContactRoute }
export type SandboxMapTarget = SandboxMapTargetV18

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  return buildComponentSandboxHtmlV18(targets as unknown as SandboxMapTargetV18[])
}
