import 'package:flutter/material.dart';
import '../services/server_data_service.dart';

// --- MODERN THEME COLORS ---
class NoteTheme {
  static const Color primary = Color(0xFF2563EB);
  static const Color surface = Colors.white;
  static const Color background = Color(0xFFF8FAFC);
  static const Color textMain = Color(0xFF1E293B);
  static const Color textSub = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);
  static const Color warningBg = Color(0xFFFFF7ED);
  static const Color warningText = Color(0xFFC2410C);
}

class NotesDialog extends StatefulWidget {
  final int opdId;

  const NotesDialog({super.key, required this.opdId});

  @override
  State<NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<NotesDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    // Fetch existing note from the ServerDataService
    var data = await ServerDataService.fetchData(widget.opdId, 'clinical_notes');
    if (data != null && data is String) {
      if (mounted) setState(() => _controller.text = data);
    }
  }

  Future<void> _saveNote() async {
    setState(() => _isSaving = true);

    // 1. Save to Cloud
    // The Bill/Preview tab reads from this exact key ('clinical_notes')
    await ServerDataService.saveData(widget.opdId, 'clinical_notes', _controller.text);

    // Simulate a brief network delay for UX feedback
    await Future.delayed(const Duration(milliseconds: 400));

    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.pop(context); // Close dialog

      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text("Notes saved & updated on Bill"),
              ],
            ),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: NoteTheme.surface,
      elevation: 10,
      child: Container(
        width: 500, // Fixed professional width
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: NoteTheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HEADER ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Clinical Notes", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: NoteTheme.textMain)),
                    Text("Private remarks & observations", style: TextStyle(fontSize: 12, color: NoteTheme.textSub)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: NoteTheme.warningBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: NoteTheme.warningText.withOpacity(0.2))
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_outline, size: 12, color: NoteTheme.warningText),
                      SizedBox(width: 4),
                      Text("Internal Only", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: NoteTheme.warningText)),
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(height: 20),

            // --- TEXT AREA ---
            Container(
              decoration: BoxDecoration(
                  color: NoteTheme.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NoteTheme.border),
                  ),
              child: TextField(
                controller: _controller,
                maxLines: 10,
                style: const TextStyle(fontSize: 14, height: 1.5, color: NoteTheme.textMain),
                decoration: const InputDecoration(
                  hintText: "• Patient history details...\n• Specific observations...\n• Internal remarks...",
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // --- FOOTER ACTIONS ---
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: NoteTheme.textSub),
                  child: const Text("Cancel"),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveNote,
                  icon: _isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(_isSaving ? "Saving..." : "Save Note"),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: NoteTheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}