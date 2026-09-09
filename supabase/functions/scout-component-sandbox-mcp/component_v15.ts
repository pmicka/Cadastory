import {
  buildComponentSandboxHtml as buildComponentSandboxHtmlV14,
  type SandboxMapMember,
  type SandboxMapTarget as SandboxMapTargetV14,
  type SandboxMapTerritory,
  type SandboxContactCard,
  type SandboxContactRoute,
} from './component_v14.ts'

export type { SandboxMapMember, SandboxMapTerritory, SandboxContactCard, SandboxContactRoute }
export type SandboxMapTarget = SandboxMapTargetV14

function replaceRequired(source:string, needle:string, replacement:string, label:string){
  if(!source.includes(needle))throw new Error('Scout component sandbox v15 transform failed: '+label)
  return source.replace(needle,replacement)
}

const oldOpen="if(host.openExternal)await host.openExternal({href});else window.open(href,'_blank','noopener,noreferrer');"
const newOpen="if(host.openExternal)await host.openExternal({href,redirectUrl:false});else window.open(href,'_blank','noopener,noreferrer');"

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV14(targets as unknown as SandboxMapTargetV14[])
  html=replaceRequired(html,oldOpen,newOpen,'direct vCard redirect')
  return html
}
