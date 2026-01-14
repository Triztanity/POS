import 'package:flutter/material.dart';

/// Location selector widget that shows a compact row with left/right arrows
/// and when tapped opens a searchable bottom sheet for picking an item.
///
/// Usage:
/// ```dart
/// LocationSelectorBottomSheet(
///   label: 'FROM',
///   value: currentValue,
///   options: locations,
///   onSelected: (v) => setState(() => currentValue = v),
///   onLeft: () => setState(() => ...),
///   onRight: () => setState(() => ...),
/// )
/// ```
class LocationSelectorBottomSheet extends StatefulWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const LocationSelectorBottomSheet({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    this.onLeft,
    this.onRight,
  });

  @override
  State<LocationSelectorBottomSheet> createState() =>
      _LocationSelectorBottomSheetState();
}

class _LocationSelectorBottomSheetState
    extends State<LocationSelectorBottomSheet> {
  void _openSearchableSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return _SearchableLocationSheet(
          label: widget.label,
          options: widget.options,
          currentValue: widget.value,
          onSelected: (v) {
            widget.onSelected(v);
            Navigator.of(ctx).pop();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Compact row that looks like the UI blueprint: label on left, arrows + value on right.
    return GestureDetector(
      onTap: _openSearchableSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green[700]!.withOpacity(0.08), // subtle green background
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            // Label
            Expanded(
              flex: 3,
              child: Text(
                widget.label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
            ),

            // Left arrow
            IconButton(
              onPressed: widget.onLeft,
              icon: const Icon(Icons.chevron_left),
              splashRadius: 20,
            ),

            // Value (center)
            Expanded(
              flex: 6,
              child: Center(
                child: Text(
                  widget.value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            // Right arrow
            IconButton(
              onPressed: widget.onRight,
              icon: const Icon(Icons.chevron_right),
              splashRadius: 20,
            ),

            const SizedBox(width: 4),

            // Drop-down indicator (tappable area also triggers bottom sheet)
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// Internal widget: searchable bottom sheet content.
class _SearchableLocationSheet extends StatefulWidget {
  final String label;
  final List<String> options;
  final String currentValue;
  final ValueChanged<String> onSelected;

  const _SearchableLocationSheet({
    required this.label,
    required this.options,
    required this.currentValue,
    required this.onSelected,
  });

  @override
  State<_SearchableLocationSheet> createState() =>
      _SearchableLocationSheetState();
}

class _SearchableLocationSheetState extends State<_SearchableLocationSheet> {
  late List<String> filtered;
  String query = '';

  @override
  void initState() {
    super.initState();
    filtered = List<String>.from(widget.options);
  }

  void _onSearchChanged(String text) {
    setState(() {
      query = text;
      filtered = widget.options
          .where((s) => s.toLowerCase().contains(text.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Use MediaQuery to allow the sheet to expand to a useful height on phones.
    final height = MediaQuery.of(context).size.height * 0.6;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle and header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Select ${widget.label}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search ${widget.label.toLowerCase()}',
                  prefixIcon: const Icon(Icons.search),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 6),

            // List of options
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No matches'))
                  : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  final isSelected = item == widget.currentValue;
                  return ListTile(
                    title: Text(item),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () => widget.onSelected(item),
                    contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  );
                },
              ),
            ),

            // Optional footer: quick actions (clear search, close)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      _onSearchChanged('');
                      FocusScope.of(context).unfocus();
                    },
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
