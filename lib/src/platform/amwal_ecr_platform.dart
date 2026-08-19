import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../model/ecr_inquiry.dart';
import '../model/ecr_receipt.dart';
import '../model/ecr_result.dart';
import 'amwal_ecr_method_channel.dart';
import 'ecr_request.dart';

/// The seam between the Dart API and whatever drives the terminal.
///
/// Federated so a test can stand in for the host without a binding, and so a
/// future platform — a desktop till, a web bridge — can be added without the
/// public API changing shape.
///
/// Implementations must hold to the same rules the native hosts do:
///
/// * **exactly one completion per call**, and never a second one after a
///   cancel;
/// * **no retry of any kind.** Nothing in this package may send a money-moving
///   request the caller did not ask for. A duplicate submission is a customer
///   charged twice, and there is no failure worth that;
/// * a failure whose outcome is unknown is reported as such, never as a
///   decline.
abstract base class AmwalEcrPlatform extends PlatformInterface {
  /// Registers the subclass against the interface's token, which is what
  /// stops an unrelated object being installed as [instance].
  AmwalEcrPlatform() : super(token: _token);

  static final Object _token = Object();

  static AmwalEcrPlatform _instance = MethodChannelAmwalEcr();

  /// The implementation in use. Defaults to the method-channel host.
  static AmwalEcrPlatform get instance => _instance;

  static set instance(AmwalEcrPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Whether the terminal is listening. Never throws: an unreachable terminal
  /// is an answer, not an error.
  Future<bool> isReachable(EcrRequest request);

  /// Takes a payment.
  Future<EcrResult> sale(EcrRequest request);

  /// Cancels an earlier transaction in full.
  Future<EcrResult> voidTransaction(EcrRequest request);

  /// Returns money against an earlier transaction.
  Future<EcrResult> refund(EcrRequest request);

  /// Asks what became of an earlier transaction, by its receipt number.
  Future<EcrInquiry> inquire(EcrRequest request);

  /// Asks what became of an earlier transaction, by the reference it was sent
  /// with.
  ///
  /// The only lookup available after an answer goes missing: a receipt number
  /// arrives *in* the answer, and the reference does not.
  Future<EcrInquiry> inquireByReference(EcrRequest request);

  /// Fetches an earlier transaction's e-receipt.
  Future<EcrReceipt> receipt(EcrRequest request);

  /// Asks the host to abandon the operation with [operationId].
  ///
  /// Answers whether an operation was still running. `false` means it had
  /// already finished — its real outcome is on its own future, and nothing was
  /// interrupted.
  Future<bool> cancel(String operationId);
}
