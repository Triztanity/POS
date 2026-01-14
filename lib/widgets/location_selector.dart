import 'package:flutter/material.dart';

/// Inline dropdown-style location selector with optional left/right arrows.
/// Uses DropdownButtonFormField for the dropdown popup (clean white list).
class LocationSelector extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final bool showArrows;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const LocationSelector({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.showArrows = false,
    this.onLeft,
    this.onRight,
  });

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: screenW * 0.03, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Label left
          SizedBox(
            width: screenW * 0.18,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),

          if (showArrows) ...[
            IconButton(
              onPressed: onLeft,
              icon: const Icon(Icons.chevron_left),
              splashRadius: 20,
            ),
          ],

          // Expanded dropdown area
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: value,
              isExpanded: true,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                filled: false,
                border: InputBorder.none,
              ),
              icon: const Icon(Icons.arrow_drop_down),
              dropdownColor: Colors.white,
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
              items: options.map((opt) {
                return DropdownMenuItem<String>(
                  value: opt,
                  child: Text(opt),
                );
              }).toList(),
            ),
          ),

          if (showArrows) ...[
            IconButton(
              onPressed: onRight,
              icon: const Icon(Icons.chevron_right),
              splashRadius: 20,
            ),
          ],
        ],
      ),
    );
  }
}
