import 'jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.115.0'
import { createHomeGalleryUploadsHandler } from './handler.ts'
import { processPhoto } from '../farm-watch-pin-photos/image.ts'

const url=Deno.env.get('SUPABASE_URL')!
const publishable=Deno.env.get('SUPABASE_ANON_KEY')!
// Service credentials perform only object Storage I/O after user-scoped RPCs.
const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{
  auth:{persistSession:false,autoRefreshToken:false},
})
Deno.serve(createHomeGalleryUploadsHandler(
  token=>createClient(url,publishable,{
    global:{headers:{Authorization:`Bearer ${token}`}},
    auth:{persistSession:false,autoRefreshToken:false},
  }),
  ()=>admin,
  processPhoto,
))
