import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../components/omr_symbol.dart';
import 'transaction_state.dart';

/// Approved green and declined red, as the Android example's theme names them.
const Color approvedGreen = Color(0xFF1B8E3C);
const Color declinedRed = Color(0xFFC5303A);

/// How a transaction ended: the outcome at a glance, the fields that matter to
/// a cashier, and the terminal's full answer tucked away for when it does not
/// add up.
///
/// Mirrors `TransactionResultDialog.kt`.
class TransactionResultDialog extends StatelessWidget {
  const TransactionResultDialog({
    super.key,
    required this.result,
    required this.type,
    required this.onDismiss,
    this.onPrintReceipt,
    this.onCloseReceipt,
  });

  final EcrResult result;
  final EcrTransactionType type;
  final VoidCallback onDismiss;

  /// Asks the terminal to put its receipt away. Null hides the button: the
  /// terminal cannot be asked over this transport.
  final VoidCallback? onCloseReceipt;

  /// App-to-app only: ask the payment app to print an image built from this
  /// operation's result. Null hides the button.
  final VoidCallback? onPrintReceipt;

  @override
  Widget build(BuildContext context) {
    return switch (result) {
      final EcrApproved approved => _ApprovedDialog(
          result: approved,
          type: type,
          onDismiss: onDismiss,
          onPrintReceipt: onPrintReceipt,
          onCloseReceipt: onCloseReceipt,
        ),
      final EcrDeclined declined => _DeclinedDialog(
          result: declined,
          onDismiss: onDismiss,
          onCloseReceipt: onCloseReceipt,
        ),
      // No reference offered here: this route shows a result that already
      // arrived. The unknown-outcome case comes through TransactionFailed,
      // which carries the reference to ask about.
      final EcrFailed failed => TransactionFailureDialog(
          reason: failed.failure.message,
          onDismiss: onDismiss,
        ),
    };
  }
}

class _ApprovedDialog extends StatelessWidget {
  const _ApprovedDialog({
    required this.result,
    required this.type,
    required this.onDismiss,
    this.onPrintReceipt,
    this.onCloseReceipt,
  });

  final EcrApproved result;
  final EcrTransactionType type;
  final VoidCallback onDismiss;
  final VoidCallback? onPrintReceipt;
  final VoidCallback? onCloseReceipt;

  @override
  Widget build(BuildContext context) {
    // A partial approval is an approval the till must act on: the customer
    // still owes the difference, so it is called out rather than shown as a
    // plain "Approved" with a quietly smaller figure.
    return ResultDialog(
      headline: result.partialApproval ? 'Partially approved' : 'Approved',
      icon: Icons.check_circle,
      tint: approvedGreen,
      amount: result.amount,
      message: result.partialApproval
          ? 'Only ${result.amount} of ${result.requestedAmount} was approved. '
              'Collect the difference by another means.'
          // The terminal only says "Approved" here, which the headline says.
          : null,
      fields: <(String, String)>[
        // A void carries no authorisation of its own — the terminal returns a
        // placeholder — so showing one would suggest an approval that never
        // took place.
        if (type != EcrTransactionType.voidTransaction)
          ('Auth code', result.authCode),
        ('Card', result.maskedPan),
      ].where(((String, String) field) => field.$2.isNotEmpty).toList(),
      rawPayload: result.raw,
      onDismiss: onDismiss,
      onCloseReceipt: onCloseReceipt,
      extra: onPrintReceipt == null
          ? null
          : OutlinedButton.icon(
              key: const Key('printReceipt'),
              onPressed: onPrintReceipt,
              icon: const Icon(Icons.print),
              label: const Text('Print receipt'),
            ),
    );
  }
}

class _DeclinedDialog extends StatelessWidget {
  const _DeclinedDialog({
    required this.result,
    required this.onDismiss,
    this.onCloseReceipt,
  });

  final EcrDeclined result;
  final VoidCallback onDismiss;
  final VoidCallback? onCloseReceipt;

  @override
  Widget build(BuildContext context) {
    return ResultDialog(
      headline: 'Declined',
      icon: Icons.cancel,
      tint: declinedRed,
      amount: '',
      message: EcrWireResponse.displayMessageFromRaw(
        result.raw,
        fallback: result.reason,
      ),
      fields: const <(String, String)>[],
      rawPayload: result.raw.isNotEmpty ? result.raw : null,
      onDismiss: onDismiss,
      onCloseReceipt: onCloseReceipt,
    );
  }
}

/// What the terminal knows about an earlier transaction.
///
/// The headline is the transaction's own status, not the inquiry's: an inquiry
/// that finds a declined sale succeeded, and the till needs to read "Declined".
class InquiryResultDialog extends StatelessWidget {
  const InquiryResultDialog({
    super.key,
    required this.state,
    required this.onRequestReceipt,
    required this.onDismiss,
    this.operationTimer,
    this.onCancelFetch,
  });

  final TransactionInquired state;
  final VoidCallback onRequestReceipt;
  final VoidCallback onDismiss;
  final OperationTimer? operationTimer;
  final VoidCallback? onCancelFetch;

  @override
  Widget build(BuildContext context) {
    switch (state.inquiry) {
      case EcrInquiryFailed(:final EcrFailure failure):
        return TransactionFailureDialog(
          reason: failure.message,
          onDismiss: onDismiss,
        );

      case EcrInquiryNotFound(:final String reason, :final String raw):
        return ResultDialog(
          headline: 'Not found',
          icon: Icons.cancel,
          tint: declinedRed,
          amount: '',
          message: EcrWireResponse.displayMessageFromRaw(
            raw,
            fallback: reason,
          ),
          fields: const <(String, String)>[],
          rawPayload: raw,
          onDismiss: onDismiss,
        );

      case EcrInquiryFound(:final EcrTransaction transaction, :final String raw):
        final bool settled = transaction.status.toLowerCase() == 'approved';
        // A partial approval read back from an inquiry is the same fact the
        // sale reported, and has to read the same. Showing `amount` alone said
        // "Approved · 961.100" for a transaction where 50.000 was taken: the
        // sale screen called that out and this one did not, so one payment
        // looked like two different things depending on how it was reached.
        final bool partial = settled && transaction.partialApproval;
        return ResultDialog(
          headline: partial
              ? 'Partially approved'
              : transaction.status.isEmpty
              ? 'Found'
              : transaction.status,
          icon: settled ? Icons.check_circle : Icons.cancel,
          tint: settled ? approvedGreen : declinedRed,
          amount: partial ? transaction.authorizedAmount : transaction.amount,
          message: partial
              ? 'Only ${transaction.authorizedAmount} of ${transaction.amount} '
                    'was approved. Collect the difference by another means.'
              : settled
              ? null
              : EcrWireResponse.displayMessageFromRaw(
                  raw,
                  fallback: transaction.status,
                ),
          // What a till needs to recognise the transaction. The rest of the
          // record is a tap away under the raw response.
          fields: <(String, String)>[
            ('Receipt number', transaction.stan),
            ('Type', transaction.type),
            ('Card', transaction.maskedPan),
            ('Date/Time', _readableTime(transaction.transactionTime)),
          ].where(((String, String) field) => field.$2.isNotEmpty).toList(),
          rawPayload: raw,
          onDismiss: onDismiss,
          extra: _ReceiptSection(
            receipt: state.receipt,
            fetching: state.fetchingReceipt,
            operationTimer: operationTimer,
            onRequestReceipt: onRequestReceipt,
            onCancelFetch: onCancelFetch,
          ),
        );
    }
  }
}

/// The e-receipt: a button until it is asked for, then the QR code itself.
///
/// The customer scans it and reads the receipt on their own phone, so a till
/// with no printer can still hand one over.
class _ReceiptSection extends StatelessWidget {
  const _ReceiptSection({
    required this.receipt,
    required this.fetching,
    required this.onRequestReceipt,
    this.operationTimer,
    this.onCancelFetch,
  });

  final EcrReceipt? receipt;
  final bool fetching;
  final OperationTimer? operationTimer;
  final VoidCallback onRequestReceipt;
  final VoidCallback? onCancelFetch;

  @override
  Widget build(BuildContext context) {
    if (fetching) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OperationCountdownBanner(
            status: 'Fetching the receipt…',
            timer: operationTimer,
          ),
          if (onCancelFetch != null) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('cancelOperation'),
              onPressed: onCancelFetch,
              child: const Text('Cancel operation'),
            ),
          ],
        ],
      );
    }

    return switch (receipt) {
      EcrReceiptReady(:final String url) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Scan for the receipt'),
            const SizedBox(height: 8),
            // Tightly sized on purpose. QrImageView builds a LayoutBuilder,
            // which cannot answer an intrinsic-width query — and AlertDialog
            // asks for one when it measures its content. A SizedBox with both
            // dimensions fixed answers from its own constraints and never
            // consults the child, so the question stops there.
            SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(
                key: const Key('receiptQr'),
                data: url,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          ],
        ),
      EcrReceiptUnavailable(:final String reason) => Text(
          reason.isEmpty
              ? 'No receipt is available for this transaction'
              : reason,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      EcrReceiptFailed(:final EcrFailure failure) => Text(
          failure.message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      _ => OutlinedButton.icon(
          key: const Key('qrReceipt'),
          onPressed: onRequestReceipt,
          icon: const Icon(Icons.qr_code_2),
          label: const Text('QR receipt'),
        ),
    };
  }
}

/// The exchange itself failed: unreachable, timed out, malformed.
class TransactionFailureDialog extends StatelessWidget {
  const TransactionFailureDialog({
    super.key,
    required this.reason,
    required this.onDismiss,
  });

  final String reason;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return ResultDialog(
      // Not "Declined": no answer came back, so nobody knows yet. The wording
      // has to stop an operator concluding the payment did not happen.
      headline: 'Not completed',
      icon: Icons.cancel,
      tint: declinedRed,
      amount: '',
      message: reason,
      fields: const <(String, String)>[],
      rawPayload: null,
      onDismiss: onDismiss,
    );
  }
}

/// Spinner + countdown while a sale / void / inquiry / receipt fetch is running.
class OperationCountdownBanner extends StatelessWidget {
  const OperationCountdownBanner({
    super.key,
    required this.status,
    required this.timer,
  });

  final String status;
  final OperationTimer? timer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final OperationTimer? current = timer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(status, key: const Key('busyLabel')),
                  if (current != null) ...<Widget>[
                    Text(
                      current.label,
                      key: const Key('operationCountdown'),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Text(
                      'remaining of ${current.totalSeconds} s timeout',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (current != null) ...<Widget>[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: current.progress),
        ],
      ],
    );
  }
}

/// The shape every outcome is shown in.
class ResultDialog extends StatefulWidget {
  const ResultDialog({
    super.key,
    required this.headline,
    required this.icon,
    required this.tint,
    required this.amount,
    required this.message,
    required this.fields,
    required this.rawPayload,
    required this.onDismiss,
    this.onCloseReceipt,
    this.extra,
  });

  final String headline;
  final IconData icon;
  final Color tint;

  /// In major units. Empty where there is no figure worth showing.
  final String amount;

  final String? message;
  final List<(String, String)> fields;

  /// The terminal's whole answer, shown only when the operator asks for it.
  final String? rawPayload;

  final VoidCallback onDismiss;

  /// Shown next to Close when set. Close only dismisses this dialog; this is
  /// what clears the terminal's screen.
  final VoidCallback? onCloseReceipt;
  final Widget? extra;

  @override
  State<ResultDialog> createState() => _ResultDialogState();
}

class _ResultDialogState extends State<ResultDialog> {
  bool _showRaw = false;

  Future<void> _copyRawPayload() async {
    final String? payload = widget.rawPayload;
    if (payload == null || payload.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Raw response copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('resultDialog'),
      icon: Icon(widget.icon, color: widget.tint, size: 48),
      title: Text(
        widget.headline,
        key: const Key('resultHeadline'),
        textAlign: TextAlign.center,
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.amount.isNotEmpty) ...<Widget>[
              Row(
                // Centred against the dialog rather than against its own
                // width, so it stays under the headline whatever else the
                // dialog is showing.
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  const OmrSymbol(),
                  const SizedBox(width: 6),
                  Text(
                    widget.amount,
                    key: const Key('resultAmount'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (widget.message != null && widget.message!.isNotEmpty) ...<Widget>[
              Text(widget.message!, key: const Key('resultMessage')),
              const SizedBox(height: 12),
            ],
            for (final (String, String) field in widget.fields)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(field.$1),
                    Text(
                      field.$2,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            if (widget.extra != null) ...<Widget>[
              const SizedBox(height: 16),
              widget.extra!,
            ],
            if (widget.rawPayload != null) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  TextButton(
                    key: const Key('toggleRaw'),
                    onPressed: () => setState(() => _showRaw = !_showRaw),
                    child: Text(_showRaw ? 'Hide raw response' : 'Raw response'),
                  ),
                  if (_showRaw) ...<Widget>[
                    const Spacer(),
                    IconButton(
                      key: const Key('copyRaw'),
                      tooltip: 'Copy raw response',
                      icon: const Icon(Icons.copy),
                      onPressed: _copyRawPayload,
                    ),
                  ],
                ],
              ),
              if (_showRaw)
                SelectableText(
                  widget.rawPayload!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        if (widget.onCloseReceipt != null)
          TextButton(
            key: const Key('closeTerminalReceipt'),
            onPressed: widget.onCloseReceipt,
            child: const Text('Close receipt'),
          ),
        TextButton(
          key: const Key('dismissResult'),
          onPressed: widget.onDismiss,
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// `2026-08-09T16:58:16.804271` reads as `09 Aug 2026, 16:58`.
String _readableTime(String isoTime) {
  final DateTime? parsed = DateTime.tryParse(isoTime);
  if (parsed == null) return isoTime;
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${parsed.day.toString().padLeft(2, '0')} '
      '${months[parsed.month - 1]} ${parsed.year}, '
      '${parsed.hour.toString().padLeft(2, '0')}:'
      '${parsed.minute.toString().padLeft(2, '0')}';
}
