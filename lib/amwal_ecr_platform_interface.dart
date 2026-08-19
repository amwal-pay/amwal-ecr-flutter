/// The seam an alternative host implements, and the channel contract it has to
/// honour.
///
/// Import this only to write a platform implementation or a fake for tests —
/// application code wants `package:amwal_ecr/amwal_ecr.dart`.
library amwal_ecr_platform_interface;

export 'src/platform/amwal_ecr_method_channel.dart';
export 'src/platform/amwal_ecr_platform.dart';
export 'src/platform/ecr_channel_contract.dart';
export 'src/platform/ecr_codec.dart';
export 'src/platform/ecr_request.dart';
