import chunk00 from './view-chunks/chunk00.ts'
import chunk01 from './view-chunks/chunk01.ts'
import chunk02 from './view-chunks/chunk02.ts'
import chunk03 from './view-chunks/chunk03.ts'

const encoded = [chunk00, chunk01, chunk02, chunk03].join('')
const compressed = Uint8Array.from(atob(encoded), (character) => character.charCodeAt(0))
const stream = new Blob([compressed]).stream().pipeThrough(new DecompressionStream('gzip'))
export const SCOUT_VIEW_HTML = await new Response(stream).text()
