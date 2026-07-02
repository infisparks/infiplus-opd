import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FullScreenSearchPage extends StatefulWidget {
  final String title;
  final String hintText;
  final List<String>? allItems; 
  final Future<List<String>> Function(String)? onSearch; 
  final Function(String) onItemSelected;
  final Function(String)? onItemRemoved;

  const FullScreenSearchPage({
    Key? key,
    required this.title,
    required this.hintText,
    this.allItems,
    this.onSearch,
    required this.onItemSelected,
    this.onItemRemoved,
  }) : super(key: key);

  @override
  State<FullScreenSearchPage> createState() => _FullScreenSearchPageState();
}

class _FullScreenSearchPageState extends State<FullScreenSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _searchQuery = "";
  List<String> _recentlyAdded = [];
  List<String> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    
    // ── NAVIGATION LAG FIX: Delay heavy operations until transition completes ──
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        
        // 1. Fetch initial results AFTER transition
        if (widget.onSearch != null) {
          _fetchInitialResults();
        } else if (widget.allItems != null) {
          setState(() {
            _searchResults = widget.allItems!.toSet().toList();
          });
        }
        
        // 2. Request focus AFTER transition
        _focusNode.requestFocus();
      });
    });
  }

  Future<void> _fetchInitialResults() async {
    if (!mounted) return;
    setState(() => _isSearching = true);
    try {
      final results = await widget.onSearch!("");
      if (mounted) {
        setState(() {
          _searchResults = results.toSet().toList();
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    if (query.isEmpty) {
      _fetchInitialResults();
      setState(() {
        _searchQuery = "";
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() {
        _searchQuery = query;
        _isSearching = true;
      });

      try {
        if (widget.onSearch != null) {
          final results = await widget.onSearch!(query);
          if (mounted) {
            setState(() {
              _searchResults = results.toSet().toList();
              _isSearching = false;
            });
          }
        } else if (widget.allItems != null) {
          setState(() {
            _searchResults = widget.allItems!
                .where((element) => element.toLowerCase().contains(query.toLowerCase()))
                .toSet()
                .toList();
            _isSearching = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  void _handleSelect(String item) {
    widget.onItemSelected(item);
    setState(() {
      if (!_recentlyAdded.contains(item)) {
        _recentlyAdded.insert(0, item);
      }
      _searchController.clear();
      _searchQuery = "";
      if (widget.onSearch == null && widget.allItems != null) {
        _searchResults = widget.allItems!.toSet().toList();
      } else {
        // Refresh list after selection
        _fetchInitialResults();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const Color primaryColor = Color(0xFF6366F1);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.title, style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600, fontSize: 16)),
        actions: [
          if (_searchQuery.isEmpty && _recentlyAdded.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("DONE", style: TextStyle(color: primaryColor, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: (_recentlyAdded.isNotEmpty && _searchQuery.isEmpty)
        ? FloatingActionButton.extended(
            onPressed: () => Navigator.pop(context),
            backgroundColor: primaryColor,
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
            label: const Text("FINISH", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
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
                focusNode: _focusNode,
                onChanged: _onSearchChanged,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
                  suffixIcon: _isSearching 
                    ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor)))
                    : _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Color(0xFF94A3B8)),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged("");
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),

          // Add New Button
          if (_searchResults.isEmpty && _searchQuery.isNotEmpty && !_isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: InkWell(
                onTap: () => _handleSelect(_searchQuery.trim()),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: primaryColor.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: primaryColor.withOpacity(0.2))),
                  child: Row(
                    children: [
                      const Icon(Icons.add_circle_outline_rounded, color: primaryColor),
                      const SizedBox(width: 12),
                      Expanded(child: Text("Add '$_searchQuery' as new", style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A), fontWeight: FontWeight.w600))),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: primaryColor),
                    ],
                  ),
                ),
              ),
            ),

          if (_recentlyAdded.isNotEmpty && _searchQuery.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: const Text("Recently Added (Tap 'X' to remove)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
            ),

          if (_recentlyAdded.isNotEmpty && _searchQuery.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _recentlyAdded.map((item) => InputChip(
                  label: Text(item, style: const TextStyle(fontSize: 13, color: primaryColor, fontWeight: FontWeight.w500)),
                  backgroundColor: primaryColor.withOpacity(0.1),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  deleteIcon: const Icon(Icons.cancel, color: primaryColor, size: 20),
                  onDeleted: () {
                    setState(() => _recentlyAdded.remove(item));
                    widget.onItemRemoved?.call(item);
                  },
                )).toList(),
              ),
            ),

          if (_recentlyAdded.isNotEmpty && _searchQuery.isEmpty) const SizedBox(height: 16),

          // Search Results
          Expanded(
            child: (_isSearching && _searchResults.isEmpty)
              ? const Center(child: CircularProgressIndicator())
              : (_searchResults.isEmpty && _searchQuery.isEmpty && widget.onSearch != null)
                ? const Center(child: CircularProgressIndicator()) // Initial delay loading
                : (_searchResults.isEmpty && _searchQuery.isNotEmpty)
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.search_off_rounded, size: 64, color: Color(0xFFCBD5E1)), const SizedBox(height: 16), const Text("No matches found", style: TextStyle(fontSize: 14, color: Color(0xFF64748B)))]))
                  : SingleChildScrollView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: RepaintBoundary(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 10,
                            children: _searchResults.asMap().entries.map((entry) {
                              final index = entry.key;
                              final item = entry.value;
                              return Material(
                                key: ValueKey('$item-$index'),
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _handleSelect(item),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.add_circle_outline_rounded, color: primaryColor, size: 14),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            item,
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF0F172A)),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}
