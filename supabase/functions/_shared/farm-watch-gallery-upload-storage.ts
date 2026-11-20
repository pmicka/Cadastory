export const HOME_GALLERY_UPLOAD_BUCKET = 'farm-watch-home-gallery-uploads'
const STAGED_PATH = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.webp$/

// All privileged deletes originate from the database queue, and failures
// remain queued. No client paths may be passed through to Storage.
export async function cleanHomeGalleryUploads(admin: any, queuedPath?: string) {
  try {
    const { data, error } = await admin.rpc('farm_watch_home_gallery_upload_cleanup_v1',
      queuedPath ? { p_queue_path: queuedPath } : {})
    if (error || !Array.isArray(data?.paths) || !data.paths.length ||
        data.paths.length > 20 || data.paths.some((path: unknown) =>
        typeof path !== 'string' || !STAGED_PATH.test(path))) return
    const removed = await admin.storage.from(HOME_GALLERY_UPLOAD_BUCKET).remove(data.paths)
    if (!removed.error) await admin.rpc('farm_watch_home_gallery_upload_cleanup_v1',
      { p_ack_paths: data.paths })
  } catch {
    // Keep the DB outbox; retry upon the next authorized operation.
  }
}
