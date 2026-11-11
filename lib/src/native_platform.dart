import 'dart:io' show Platform;

/// Whether this platform has a native implementation.
///
/// Compared as a string instead of [Platform.isOhos] so the package still
/// builds on Flutter SDKs that don't know about OpenHarmony.
bool get isNativePlatform =>
    Platform.isAndroid || Platform.isIOS || Platform.operatingSystem == 'ohos';
