// Native previews use the original local-file video player. Web video uploads
// have bytes, not a filesystem path, so keep browser compilation independent.
export 'picked_video_preview_web.dart'
    if (dart.library.io) 'picked_video_preview_io.dart';
