/// Drive an Amwal POS terminal from Flutter, on Android and iOS, through one
/// Dart API.
///
/// ```dart
/// import 'package:amwal_ecr/amwal_ecr.dart';
///
/// final EcrTerminal terminal = EcrTerminal(
///   host: '192.168.1.50',
///   serialNumber: 'P653200085189',
///   transport: EcrTransport.wifi,
/// );
///
/// if (!await terminal.isReachable()) return;
///
/// switch (await terminal.sale(EcrAmount.parse('1.234'))) {
///   case EcrApproved(:final String amount, :final String rrn):
///     print('Took $amount, RRN $rrn');
///   case EcrDeclined(:final String reason):
///     print('Refused: $reason');
///   case EcrFailed(:final EcrFailure failure) when failure.outcomeIsUnknown:
///     // Do not retry. Ask the terminal what happened.
///     print('Unknown: ${failure.message}');
///   case EcrFailed(:final EcrFailure failure):
///     print('Failed: ${failure.message}');
/// }
/// ```
///
/// See `doc/integration-guide.md` for the whole of it, and
/// `doc/compatibility-matrix.md` for where the two platforms differ.
library amwal_ecr;

export 'src/ecr_operation.dart';
export 'src/ecr_terminal.dart';
export 'src/model/ecr_amount.dart';
export 'src/model/ecr_config.dart';
export 'src/model/ecr_errors.dart';
export 'src/model/ecr_failure.dart';
export 'src/model/ecr_inquiry.dart';
export 'src/model/ecr_next_step.dart';
export 'src/model/ecr_receipt.dart';
export 'src/model/ecr_response_code.dart';
export 'src/model/ecr_result.dart';
export 'src/model/ecr_transaction.dart';
export 'src/model/ecr_transaction_type.dart';
export 'src/model/ecr_transport.dart';
