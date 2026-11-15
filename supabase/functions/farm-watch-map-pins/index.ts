import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import { cleanPinPhotos } from '../_shared/farm-watch-pin-photo-storage.ts'
import { createMapPinsHandler } from './handler.ts'

const url = Deno.env.get('SUPABASE_URL')!
const key = Deno.env.get('SUPABASE_ANON_KEY')!
let storageAdmin: ReturnType<typeof createClient> | undefined
Deno.serve(createMapPinsHandler(token => createClient(url, key, {
  global: { headers: { Authorization: `Bearer ${token}` } },
  auth: { persistSession: false, autoRefreshToken: false },
}),()=>cleanPinPhotos(storageAdmin ||= createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}}))))
