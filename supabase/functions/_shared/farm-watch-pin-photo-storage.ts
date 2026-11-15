export const PHOTO_BUCKET = 'farm-watch-pin-photos'
// Privileged Storage operations are bounded by paths from the private outbox.
// Retain the queue on failure; the next mutation retries without exposing paths.
export async function cleanPinPhotos(admin: any, queuedPath?: string) {
  try {
    const { data, error } = await admin.rpc('farm_watch_pin_photo_cleanup_v1', queuedPath ? { p_queue_path: queuedPath } : {})
    if (error || !Array.isArray(data?.paths) || !data.paths.length) return
    if (data.paths.length>20 || data.paths.some((path: unknown)=>typeof path!=='string' || !/^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.webp$/.test(path))) return
    const removed=await admin.storage.from(PHOTO_BUCKET).remove(data.paths)
    if (!removed.error) await admin.rpc('farm_watch_pin_photo_cleanup_v1',{p_ack_paths:data.paths})
  } catch { /* Retryable private cleanup; never undo a successful user mutation. */ }
}
