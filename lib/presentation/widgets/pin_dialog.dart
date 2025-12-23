import 'package:flutter/material.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';

/// Result object returned when dialog is confirmed
class PinDialogResult {
  final PinStatus status;
  final RestrictionTag? restrictionTag;
  final bool hasSecurityScreening;
  final bool hasPostedSignage;

  PinDialogResult({
    required this.status,
    this.restrictionTag,
    required this.hasSecurityScreening,
    required this.hasPostedSignage,
  });
}

/// Dialog for creating or editing a pin
class PinDialog extends StatefulWidget {
  final bool isEditMode;
  final String poiName;
  final PinStatus? initialStatus;
  final RestrictionTag? initialRestrictionTag;
  final bool initialHasSecurityScreening;
  final bool initialHasPostedSignage;
  final Function(PinDialogResult) onConfirm;
  final VoidCallback? onDelete;
  final VoidCallback onCancel;

  const PinDialog({
    super.key,
    required this.isEditMode,
    required this.poiName,
    this.initialStatus,
    this.initialRestrictionTag,
    this.initialHasSecurityScreening = false,
    this.initialHasPostedSignage = false,
    required this.onConfirm,
    this.onDelete,
    required this.onCancel,
  });

  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  late PinStatus _selectedStatus;
  RestrictionTag? _selectedRestrictionTag;
  late bool _hasSecurityScreening;
  late bool _hasPostedSignage;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.initialStatus ?? PinStatus.ALLOWED;
    _selectedRestrictionTag = widget.initialRestrictionTag;
    _hasSecurityScreening = widget.initialHasSecurityScreening;
    _hasPostedSignage = widget.initialHasPostedSignage;
  }

  bool get _isValid {
    // If NO_GUN status, must have a restriction tag
    if (_selectedStatus == PinStatus.NO_GUN) {
      return _selectedRestrictionTag != null;
    }
    return true;
  }

  void _handleConfirm() {
    if (!_isValid) return;

    widget.onConfirm(
      PinDialogResult(
        status: _selectedStatus,
        restrictionTag: _selectedRestrictionTag,
        hasSecurityScreening: _hasSecurityScreening,
        hasPostedSignage: _hasPostedSignage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Text(
                widget.isEditMode ? 'Edit Pin' : 'Create Pin',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // POI Name
              Text(
                widget.poiName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),

              // Status Selection
              Text(
                'Select carry zone status:',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 12),
              _buildStatusOption(PinStatus.ALLOWED, 'Allowed', const Color(0xFF4CAF50)),
              const SizedBox(height: 10),
              _buildStatusOption(PinStatus.UNCERTAIN, 'Uncertain', const Color(0xFFFFC107)),
              const SizedBox(height: 10),
              _buildStatusOption(PinStatus.NO_GUN, 'No Guns', const Color(0xFFF44336)),
              const SizedBox(height: 24),

              // Restriction Section (conditional)
              if (_selectedStatus == PinStatus.NO_GUN) ...[
                Text(
                  'Why is carry restricted?',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 12),
                _buildRestrictionDropdown(),
                const SizedBox(height: 24),
              ],

              // Optional Details
              Text(
                'Optional details:',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 12),
              _buildCheckbox(
                'Active security screening',
                _hasSecurityScreening,
                (value) => setState(() => _hasSecurityScreening = value ?? false),
              ),
              const SizedBox(height: 12),
              _buildCheckbox(
                'Posted signage visible',
                _hasPostedSignage,
                (value) => setState(() => _hasPostedSignage = value ?? false),
              ),
              const SizedBox(height: 24),

              // Delete Button (edit mode only)
              if (widget.isEditMode && widget.onDelete != null) ...[
                OutlinedButton.icon(
                  onPressed: widget.onDelete,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    side: const BorderSide(color: Colors.red, width: 1.5),
                  ),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text(
                    'Delete Pin',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onCancel,
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isValid ? _handleConfirm : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      backgroundColor: const Color(0xFF6200EE),
                    ),
                    child: Text(
                      widget.isEditMode ? 'Save' : 'Create',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusOption(PinStatus status, String label, Color color) {
    final isSelected = _selectedStatus == status;

    return InkWell(
      onTap: () => setState(() {
        _selectedStatus = status;
        // Clear restriction tag if switching away from NO_GUN
        if (status != PinStatus.NO_GUN) {
          _selectedRestrictionTag = null;
        }
      }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestrictionDropdown() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<RestrictionTag>(
          value: _selectedRestrictionTag,
          isExpanded: true,
          hint: const Text('Select restriction type'),
          items: RestrictionTag.values.map((tag) {
            return DropdownMenuItem(
              value: tag,
              child: Text(
                tag.displayName,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            );
          }).toList(),
          onChanged: (value) => setState(() => _selectedRestrictionTag = value),
        ),
      ),
    );
  }

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool?> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF6200EE),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(fontSize: 15),
          ),
        ],
      ),
    );
  }
}
