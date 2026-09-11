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
import chunk11 from './view-chunks/chunk11.ts'
import chunk12 from './view-chunks/chunk12.ts'
import chunk13 from './view-chunks/chunk13.ts'
import chunk14 from './view-chunks/chunk14.ts'
import chunk15 from './view-chunks/chunk15.ts'
import chunk16 from './view-chunks/chunk16.ts'

const encoded = [chunk00, chunk01, chunk02, chunk03, chunk04, chunk05, chunk06, chunk07, chunk08, chunk09, chunk10, chunk11, chunk12, chunk13, chunk14, chunk15, chunk16].join('')
const bytes = Uint8Array.from(atob(encoded), (character) => character.charCodeAt(0))
export const SCOUT_VIEW_HTML = new TextDecoder().decode(bytes)
