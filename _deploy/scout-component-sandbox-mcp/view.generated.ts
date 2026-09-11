import chunk00 from './view-chunks/chunk00.ts'
import chunk01 from './view-chunks/chunk01.ts'
import chunk02 from './view-chunks/chunk02.ts'
import chunk03 from './view-chunks/chunk03.ts'
import chunk04 from './view-chunks/chunk04.ts'
import chunk05 from './view-chunks/chunk05.ts'
import chunk06 from './view-chunks/chunk06.ts'
import chunk07 from './view-chunks/chunk07.ts'
import chunk08 from './view-chunks/chunk08.ts'
import chunk09 from './view-chunks/chunk09.ts'
import chunk10 from './view-chunks/chunk10.ts'

const encoded = [chunk00, chunk01, chunk02, chunk03, chunk04, chunk05, chunk06, chunk07, chunk08, chunk09, chunk10].join('')
const compressed = Uint8Array.from(atob(encoded), (character) => character.charCodeAt(0))
const stream = new Blob([compressed]).stream().pipeThrough(new DecompressionStream('gzip'))
export const SCOUT_VIEW_HTML = await new Response(stream).text()
