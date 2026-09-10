import {
  buildComponentSandboxHtml as buildComponentSandboxHtmlV17,
  type SandboxMapMember,
  type SandboxMapTarget as SandboxMapTargetV17,
  type SandboxMapTerritory,
  type SandboxContactCard,
  type SandboxContactRoute,
} from './component_v17.ts'

export type { SandboxMapMember, SandboxMapTerritory, SandboxContactCard, SandboxContactRoute }
export type SandboxMapTarget = SandboxMapTargetV17

function replaceRequired(source:string, needle:string, replacement:string, label:string){
  if(!source.includes(needle))throw new Error('Scout component sandbox v18 transform failed: '+label)
  return source.replace(needle,replacement)
}

const capabilityVeto="      if(!app.getHostCapabilities?.()?.downloadFile)throw new Error('host_download_file_unsupported');\n      return app;"
const directAttempt="      return app;"

const oldError="if(copy)copy.textContent=String(error?.message||'').includes('host_download_file_unsupported')?'This ChatGPT client does not currently support in-app file downloads.':'ChatGPT could not save the contact file in-app. Please try again.';"
const newError="if(copy){const message=String(error?.message||'');copy.textContent=/method not found|unsupported|not implemented|ui\\/download-file/i.test(message)?'This ChatGPT client rejected the native in-app file download request.':'ChatGPT could not save the contact file in-app. Please try again.';}"

export function buildComponentSandboxHtml(targets: SandboxMapTarget[] = []) {
  let html=buildComponentSandboxHtmlV17(targets as unknown as SandboxMapTargetV17[])
  html=replaceRequired(html,capabilityVeto,directAttempt,'direct ui/download-file attempt')
  html=replaceRequired(html,oldError,newError,'native download rejection copy')
  return html
}
