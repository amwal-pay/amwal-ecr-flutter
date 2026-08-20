import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/terminal.dart';
import '../../data/terminal_repository.dart';
import '../components/amount_field.dart';
import '../components/dropdown.dart';
import 'transaction_controller.dart';
import 'transaction_form.dart';
import 'transaction_result_dialog.dart';
import 'transaction_state.dart';

/// The till. Mirrors `TransactionScreen.kt`.
class TransactionScreen extends StatefulWidget {
  const TransactionScreen({
    super.key,
    required this.repository,
    required this.onManageTerminals,
  });

  final TerminalRepository repository;
  final Future<void> Function() onManageTerminals;

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  late final TransactionController _controller =
      TransactionController(widget.repository);

  TransactionFormState _form = TransactionFormState();
  List<Terminal> _terminals = const <Terminal>[];
  String? _selectedSerial;

  // Held rather than rebuilt each frame: a TextEditingController created inside
  // build() throws the caret back to the start on every keystroke, which on a
  // six-digit receipt number is the difference between usable and not.
  final TextEditingController _receiptNumber = TextEditingController();
  final TextEditingController _originalReference = TextEditingController();
  final TextEditingController _originalTerminalId = TextEditingController();
  final TextEditingController _originalDate = TextEditingController();

  /// Whether a result dialog is on screen, so it is shown once and not again on
  /// every rebuild.
  bool _showingResult = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onStateChanged);
    _reloadTerminals();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onStateChanged)
      ..dispose();
    _receiptNumber.dispose();
    _originalReference.dispose();
    _originalTerminalId.dispose();
    _originalDate.dispose();
    super.dispose();
  }

  Future<void> _reloadTerminals() async {
    final List<Terminal> terminals = await widget.repository.observeAll().first;
    if (!mounted) return;
    setState(() => _terminals = terminals);
  }

  /// Keep the selection pinned to its serial number as the list reloads.
  Terminal? get _terminal {
    for (final Terminal terminal in _terminals) {
      if (terminal.serialNumber == _selectedSerial) return terminal;
    }
    return _terminals.isEmpty ? null : _terminals.first;
  }

  void _onStateChanged() {
    setState(() {});
    _maybeShowResult();
  }

  /// Shown once: acknowledging returns the state to idle, and the amount is
  /// cleared so the next transaction starts fresh.
  Future<void> _maybeShowResult() async {
    if (_showingResult) return;

    final TransactionState state = _controller.state;
    final Widget? dialog = switch (state) {
      TransactionCompleted(:final EcrResult result, :final EcrTransactionType type) =>
        TransactionResultDialog(
          result: result,
          type: type,
          onDismiss: _dismissResult,
        ),
      final TransactionInquired inquired => InquiryResultDialog(
          state: inquired,
          onRequestReceipt: _controller.requestReceipt,
          onDismiss: _dismissResult,
        ),
      TransactionFailed(
        :final String message,
        :final String? inquirableReference
      ) =>
        TransactionFailureDialog(
          reason: message,
          // Offered only when the outcome is genuinely unknown. It is the one
          // action that is not a second charge, and the operator has nothing
          // else to type: the receipt number was in the answer that was lost.
          inquirableReference: inquirableReference,
          onInquire: _inquireAboutReference,
          onDismiss: _dismissResult,
        ),
      _ => null,
    };
    if (dialog == null) return;

    _showingResult = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      // Rebuilt from the controller so the inquiry dialog can show the receipt
      // once it arrives, rather than being a snapshot of the moment it opened.
      builder: (BuildContext context) => ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, Widget? _) {
          final TransactionState current = _controller.state;
          return switch (current) {
            TransactionCompleted(
              :final EcrResult result,
              :final EcrTransactionType type
            ) =>
              TransactionResultDialog(
                result: result,
                type: type,
                onDismiss: _dismissResult,
              ),
            final TransactionInquired inquired => InquiryResultDialog(
                state: inquired,
                onRequestReceipt: _controller.requestReceipt,
                onDismiss: _dismissResult,
              ),
            TransactionFailed(
              :final String message,
              :final String? inquirableReference
            ) =>
              TransactionFailureDialog(
                reason: message,
                inquirableReference: inquirableReference,
                onInquire: _inquireAboutReference,
                onDismiss: _dismissResult,
              ),
            _ => const SizedBox.shrink(),
          };
        },
      ),
    );
    _showingResult = false;
  }

  /// Looks the transaction up by the reference this till named it with, from
  /// inside the failure dialog. The dialog stays open: the inquiry replaces
  /// what it shows, so the operator sees the answer where the question was.
  void _inquireAboutReference(String reference) {
    final String? serial = _terminal?.serialNumber;
    if (serial == null) return;
    _controller.inquireAboutReference(reference, serial);
  }

  void _dismissResult() {
    Navigator.of(context).pop();
    _controller.resultAcknowledged();
    setState(() => _form = _form.copyWith(amountDigits: ''));
  }

  Future<void> _pickOriginalDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _form.originalDate,
      firstDate: DateTime(now.year - 5),
      // The original transaction cannot be in the future.
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _form = _form.copyWith(originalDate: picked));
    }
  }

  void _start() {
    final String? serial = _terminal?.serialNumber;
    if (serial == null) return;

    final (TransactionFormState validated, TransactionRequest? request) =
        _form.validated(serial);
    setState(() => _form = validated);
    if (request != null) _controller.startTransaction(request);
  }

  @override
  Widget build(BuildContext context) {
    final TransactionState state = _controller.state;
    final bool busy = state.isBusy;

    // The date field is read-only and driven entirely by the picker, so its
    // text is set from the form rather than typed into.
    _originalDate.text = _form.originalDateLabel;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ECR'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: <Widget>[
          IconButton(
            key: const Key('terminals'),
            icon: const Icon(Icons.storage),
            tooltip: 'Terminals',
            onPressed: () async {
              await widget.onManageTerminals();
              await _reloadTerminals();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Dropdown<EcrTransactionType>(
              fieldKey: const Key('transactionType'),
              label: 'Transaction type',
              options: EcrTransactionType.menuOptions,
              selected: _form.type,
              enabled: !busy,
              labelOf: (EcrTransactionType type) => type.displayName,
              // Switching type resets the choices that no longer apply, so a
              // terminal id or code left over cannot travel with the next one.
              onSelected: (EcrTransactionType type) {
                _receiptNumber.clear();
                _originalReference.clear();
                _originalTerminalId.clear();
                setState(() => _form = TransactionFormState(type: type));
              },
            ),
            const SizedBox(height: 16),

            AmountField(
              digits: _form.amountDigits,
              onDigitsChange: (String digits) =>
                  setState(() => _form = _form.copyWith(amountDigits: digits)),
              enabled: !busy && _form.type.requiresAmount,
              label: 'Amount (OMR)',
              errorMessage: _form.errors.amount,
              supportingText: switch (_form.type) {
                _ when _form.type.requiresAmount => null,
                EcrTransactionType.inquiry =>
                  'An inquiry only reads; nothing is charged',
                _ => "Uses the original transaction's amount",
              },
            ),
            const SizedBox(height: 16),

            // An inquiry can name its transaction either way. The reference is
            // the one that still works after an answer that never arrived,
            // since the receipt number was in that answer.
            if (_form.showReferenceSwitch) ...<Widget>[
              Row(
                children: <Widget>[
                  Switch(
                    key: const Key('lookUpByReference'),
                    value: _form.lookUpByReference,
                    onChanged: busy
                        ? null
                        : (bool on) {
                            _receiptNumber.clear();
                            _originalReference.clear();
                            setState(() => _form = _form.copyWith(
                                  lookUpByReference: on,
                                  receiptNumber: '',
                                  originalReference: '',
                                  errors: const FormErrors(),
                                ));
                          },
                  ),
                  const SizedBox(width: 12),
                  const Text('Look up by reference'),
                ],
              ),
              const SizedBox(height: 8),
            ],

            if (_form.looksUpByReference) ...<Widget>[
              TextField(
                key: const Key('merchantReference'),
                enabled: !busy,
                controller: _originalReference,
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(32),
                ],
                onChanged: (String value) =>
                    _form = _form.copyWith(originalReference: value),
                decoration: InputDecoration(
                  labelText: 'Merchant reference',
                  helperText: 'The reference the transaction was sent with',
                  border: const OutlineInputBorder(),
                  errorText: _form.errors.originalReference,
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_form.showReceiptNumber) ...<Widget>[
              TextField(
                key: const Key('receiptNumber'),
                enabled: !busy,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                controller: _receiptNumber,
                onChanged: (String value) =>
                    _form = _form.copyWith(receiptNumber: value),
                decoration: InputDecoration(
                  labelText: 'Receipt number',
                  helperText: 'Receipt number printed on the receipt',
                  border: const OutlineInputBorder(),
                  errorText: _form.errors.receiptNumber,
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_form.showOriginalDate) ...<Widget>[
              TextField(
                key: const Key('originalDate'),
                readOnly: true,
                enabled: !busy,
                controller: _originalDate,
                decoration: InputDecoration(
                  labelText: 'Original transaction date',
                  helperText: 'The day the original transaction was taken',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    key: const Key('pickDate'),
                    icon: const Icon(Icons.calendar_month),
                    onPressed: busy ? null : _pickOriginalDate,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // The Android example keeps the "different terminal" switch
            // commented out, so `showOriginalTerminal` is never true there and
            // no originalTerminalId is ever sent. Same here, deliberately: the
            // two apps have to send the same message.
            if (_form.showOriginalTerminal) ...<Widget>[
              TextField(
                key: const Key('originalTerminalId'),
                controller: _originalTerminalId,
                enabled: !busy,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (String value) =>
                    _form = _form.copyWith(originalTerminalId: value),
                decoration: InputDecoration(
                  labelText: 'Original terminal ID',
                  border: const OutlineInputBorder(),
                  errorText: _form.errors.originalTerminalId,
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_terminals.isEmpty)
              const Text(
                'No terminals registered yet. Add one from the Terminals screen.',
                key: Key('noTerminals'),
              )
            else
              Dropdown<Terminal>(
                fieldKey: const Key('posTerminal'),
                label: 'POS terminal',
                options: _terminals,
                selected: _terminal,
                enabled: !busy,
                labelOf: (Terminal terminal) => terminal.toString(),
                onSelected: (Terminal terminal) =>
                    setState(() => _selectedSerial = terminal.serialNumber),
              ),
            const SizedBox(height: 16),

            SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('start'),
                onPressed: (!busy && _terminal != null) ? _start : null,
                child: Text(
                  _form.type == EcrTransactionType.inquiry
                      ? 'Look up transaction'
                      : 'Start transaction',
                ),
              ),
            ),

            if (busy) ...<Widget>[
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    state is TransactionChecking
                        ? 'Checking the terminal…'
                        : 'Waiting for the POS terminal…',
                    key: const Key('busyLabel'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
