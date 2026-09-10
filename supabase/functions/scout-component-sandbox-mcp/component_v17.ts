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

function replaceRequired(source:string, needle:string, replacement:string, label:string){
  if(!source.includes(needle))throw new Error('Scout component sandbox v17 transform failed: '+label)
  return source.replace(needle,replacement)
}

const oldCarousel='.carousel{display:flex;gap:10px;overflow-x:auto;scroll-snap-type:x mandatory;scrollbar-width:none;border-radius:16px;touch-action:pan-x}'
const newCarousel='.carousel{display:flex;gap:10px;overflow-x:auto;scroll-snap-type:x proximity;scrollbar-width:none;border-radius:16px;touch-action:pan-x;overscroll-behavior-x:contain;padding-right:14%}'
const oldNarrowSlide='.slide{min-width:92%;height:190px}'
const newNarrowSlide='.carousel{padding-right:8%}.slide{min-width:92%;height:190px}'

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV18(targets as unknown as SandboxMapTargetV18[])
  html=replaceRequired(html,oldCarousel,newCarousel,'carousel snap behavior with end padding')
  html=replaceRequired(html,oldNarrowSlide,newNarrowSlide,'narrow carousel end padding')
  return html
}
