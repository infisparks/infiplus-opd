import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FullScreenSearchPage extends StatefulWidget {
  final String title;
  final String hintText;
  final List<String> allItems;
  final Function(String) onItemSelected;
  final Function(String)? onItemRemoved;

  const FullScreenSearchPage({
    Key? key,
    required this.title,
    required this.hintText,
    required this.allItems,
    required this.onItemSelected,
    this.onItemRemoved,
  }) : super(key: key);

  @override
  State<FullScreenSearchPage> createState() => _FullScreenSearchPageState();
}

class _FullScreenSearchPageState extends State<FullScreenSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  List<String> _recentlyAdded = [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleSelect(String item) {
    widget.onItemSelected(item);
    setState(() {
      if (!_recentlyAdded.contains(item)) {
        _recentlyAdded.insert(0, item);
      }
      _searchController.clear();
      _searchQuery = "";
    });
  }

  @override
  Widget build(BuildContext context) {
    List<String> filteredList = widget.allItems;
    if (_searchQuery.isNotEmpty) {
      filteredList = widget.allItems
          .where((element) => element.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    const Color primaryColor = Color(0xFF6366F1); // Indigo / Purple

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.title, style: GoogleFonts.poppins(color: const Color(0xFF0F172A), fontWeight: FontWeight.w600, fontSize: 16)),
        actions: [
          if (_searchQuery.isEmpty && _recentlyAdded.isNotEmpty)
            TextButton(
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.pop(context);
              },
              child: Text("DONE", style: GoogleFonts.poppins(color: primaryColor, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: (_recentlyAdded.isNotEmpty && _searchQuery.isEmpty)
        ? FloatingActionButton.extended(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context);
            },
            backgroundColor: primaryColor,
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
            label: Text("FINISH", 
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
          )
        : null,
      body: Column(
        children: [
          // Search Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: GoogleFonts.poppins(fontSize: 15),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: GoogleFonts.poppins(color: const Color(0xFF94A3B8)),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Color(0xFF94A3B8)),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = "");
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),

          // Integrated Add Button: Places it above keyboard and instantly visible
          if (filteredList.isEmpty && _searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Not found? Add '$_searchQuery' as new",
                        style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF0F172A), fontWeight: FontWeight.w500),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _handleSelect(_searchQuery.trim()),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text("Add"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    )
                  ],
                ),
              ),
            ),

          if (_recentlyAdded.isNotEmpty && _searchQuery.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                "Recently Added (Tap 'X' to remove)",
                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF94A3B8)),
              ),
            ),

          if (_recentlyAdded.isNotEmpty && _searchQuery.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _recentlyAdded.map((item) => InputChip(
                  label: Text(item, style: GoogleFonts.poppins(fontSize: 13, color: primaryColor, fontWeight: FontWeight.w500)),
                  backgroundColor: primaryColor.withValues(alpha: 0.1),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  deleteIcon: const Icon(Icons.cancel, color: primaryColor, size: 20),
                  onDeleted: () {
                    setState(() {
                      _recentlyAdded.remove(item);
                    });
                    widget.onItemRemoved?.call(item);
                  },
                )).toList(),
              ),
            ),

          if (_recentlyAdded.isNotEmpty && _searchQuery.isEmpty)
            const SizedBox(height: 16),

          // List
          Expanded(
            child: filteredList.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded, size: 64, color: const Color(0xFFCBD5E1)),
                          const SizedBox(height: 16),
                          Text("No results found", style: GoogleFonts.poppins(fontSize: 16, color: const Color(0xFF64748B))),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: filteredList.map((item) {
                        return InkWell(
                          onTap: () => _handleSelect(item),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.add_circle_outline_rounded, color: primaryColor, size: 16),
                                const SizedBox(width: 8),
                                Text(item, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF0F172A))),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
