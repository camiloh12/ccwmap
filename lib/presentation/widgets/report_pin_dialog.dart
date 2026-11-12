import 'package:flutter/material.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';
import 'package:ccwmap/presentation/widgets/pin_report_rules.dart';

typedef ReportSubmitCallback =
    Future<void> Function(ReportReason reason, String? note);

/// Reason picker + optional free-text note for reporting a pin.
/// Returns via [onSubmit]. The caller is responsible for popping the
/// surrounding dialog and showing the confirmation snackbar.
class ReportPinDialog extends StatefulWidget {
  final ReportSubmitCallback onSubmit;

  /// Reason options; null means the four user-pin reasons.
  final List<(ReportReason, String)>? reasons;
  final String title;
  final String? noteHint;

  const ReportPinDialog({
    super.key,
    required this.onSubmit,
    this.reasons,
    this.title = 'Report this pin',
    this.noteHint,
  });

  @override
  State<ReportPinDialog> createState() => _ReportPinDialogState();
}

class _ReportPinDialogState extends State<ReportPinDialog> {
  ReportReason? _selected;
  final TextEditingController _noteController = TextEditingController();
  bool _submitting = false;

  List<(ReportReason, String)> get _options =>
      widget.reasons ?? reportReasonsFor(imported: false);

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final reason = _selected;
    if (reason == null || _submitting) return;
    setState(() => _submitting = true);
    final note = _noteController.text.trim();
    await widget.onSubmit(reason, note.isEmpty ? null : note);
    if (!mounted) return;
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (r, label) in _options)
              RadioListTile<ReportReason>(
                value: r,
                groupValue: _selected,
                title: Text(label),
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _selected = v),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              enabled: !_submitting,
              maxLength: 500,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                helperText: widget.noteHint,
                helperMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: (_selected == null || _submitting) ? null : _handleSubmit,
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
