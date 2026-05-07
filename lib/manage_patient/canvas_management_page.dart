import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import 'dart:async';

import 'supabase_config.dart';
import 'canvas_drawing_page.dart';
import 'drawing_models.dart';
import 'ipd_structure.dart';
import 'page_layout_definitions.dart';
import '../services/new_local_storage_service.dart';
import '../services/new_sync_service.dart';
import '../widgets/sync_status_icon.dart';

class SupabaseTemplateImage {
  final String id;
  final String name;
  final String url;
  final String? url2;
  final bool isbook;
  final List<String> bookImgUrl;
  final String? tag;

  SupabaseTemplateImage({
    required this.id,
    required this.name,
    required this.url,
    this.url2,
    required this.isbook,
    required this.bookImgUrl,
    this.tag,
  });

  factory SupabaseTemplateImage.fromJson(Map<String, dynamic> json) {
    return SupabaseTemplateImage(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      url2: json['2url'],
      isbook: json['isbook'] ?? false,
      bookImgUrl: [], // Simplified
      tag: json['tag'],
    );
  }
}

class CanvasManagementPage extends StatefulWidget {
  final int opdId;
  final String uhid;
  final String patientName;

  const CanvasManagementPage({
    super.key,
    required this.opdId,
    required this.uhid,
    required this.patientName,
  });

  @override
  State<CanvasManagementPage> createState() => _CanvasManagementPageState();
}

class _CanvasManagementPageState extends State<CanvasManagementPage> {
  final SupabaseClient supabase = SupabaseConfig.client;

  String _formatTimeTo12Hr(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty || timeStr == "null") return '';
    try {
      final parts = timeStr.split(':');
      int hour = int.parse(parts[0]);
      int minute = parts.length > 1 ? int.parse(parts[1]) : 0;
      final String period = hour >= 12 ? 'PM' : 'AM';
      int displayHour = hour % 12;
      if (displayHour == 0) displayHour = 12;
      final String minuteStr = minute.toString().padLeft(2, '0');
      return "$displayHour:$minuteStr $period";
    } catch (e) {
      return timeStr;
    }
  }

  List<DrawingGroup> _drawingGroups = [];
  final Map<String, int> _lastAssignedPageNumbers = {};
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _isSaving = false;
  String _searchQuery = '';

  final Set<String> _expandedGroupNames = {};
  final Set<String> _showDeletedInGroups = {};
  final ScrollController _mainScrollController = ScrollController();
  List<SupabaseTemplateImage> _availableTemplates = [];
  RealtimeChannel? _realtimeChannel;

  final Color primaryBlue = const Color(0xFF3B82F6);
  static const Color darkText = Color(0xFF1E293B);
  static const Color mediumGreyText = Color(0xFF64748B);
  static const Color lightBackground = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadAllDetails();
  }

  Future<void> _loadAllDetails({bool isBackgroundRefresh = false}) async {
    if (!isBackgroundRefresh) {
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
    }

    try {
      // Templates
      try {
        final List<Map<String, dynamic>> templateData = await supabase
            .from('template_images')
            .select('id, name, url, 2url, isbook, tag')
            .timeout(const Duration(seconds: 15));
        _availableTemplates = templateData.map((e) => SupabaseTemplateImage.fromJson(e)).toList();
      } catch (e) {
        debugPrint("Template Error: $e");
      }

      // Pages
      final pagesResp = await supabase
          .from('ipd_pages')
          .select('id, ipd_id, uhid, group_name, page_name, page_number, updated_at, is_deleted')
          .eq('uhid', widget.uhid)
          .timeout(const Duration(seconds: 45));

      _buildGroupsFromRows(List<Map<String, dynamic>>.from(pagesResp));
    } catch (e) {
      debugPrint("Critical Error loading details: $e");
      if (!isBackgroundRefresh) {
        setState(() => _loadFailed = true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _buildGroupsFromRows(List<Map<String, dynamic>> rows) {
    final Map<String, List<DrawingPage>> groupedPages = {};

    for (var config in ipdGroupStructure) {
      groupedPages[config.groupName] = [];
    }

    for (var row in rows) {
      final page = DrawingPage.fromRow(row);
      groupedPages.putIfAbsent(page.groupName, () => []).add(page);
    }

    final List<DrawingGroup> resultGroups = [];

    for (var config in ipdGroupStructure) {
      final pages = groupedPages[config.groupName]!;
      pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
      resultGroups.add(DrawingGroup(
        id: config.groupName,
        groupName: config.groupName,
        pages: pages,
      ));
      groupedPages.remove(config.groupName);
    }

    groupedPages.forEach((name, pages) {
      pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
      resultGroups.add(DrawingGroup(id: name, groupName: name, pages: pages));
    });

    setState(() {
      _drawingGroups = resultGroups;
    });
  }

  Future<void> _createPagesInDb(List<DrawingPage> newPages) async {
    if (newPages.isEmpty) return;
    setState(() => _isSaving = true);

    try {
      for (var page in newPages) {
        final row = page.toRow(widget.opdId, widget.uhid);
        row.remove('id'); // Let Supabase generate a valid UUID
        await supabase.from('ipd_pages').insert(row);
      }
      _loadAllDetails(isBackgroundRefresh: true);
    } catch (e) {
      debugPrint("Error creating pages: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }


  void _addSinglePage(DrawingGroup group, String tag, String prefix) {
    final template = _availableTemplates.firstWhere((t) => t.tag == tag, orElse: () => _availableTemplates.first);
    
    int maxPageNumber = group.pages.isEmpty ? 0 : group.pages.map((p) => p.pageNumber).reduce(max);
    final newNumber = maxPageNumber + 1;

    final newPage = DrawingPage(
        id: generateUniqueId(),
        templateImageUrl: template.url,
        pageNumber: newNumber,
        pageName: prefix,
        groupName: group.groupName
    );
    _createPagesInDb([newPage]);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text("Manage Canvas - ${widget.patientName}"),
        backgroundColor: Colors.white,
        elevation: 2,
        actions: [
          const SyncStatusIcon(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadAllDetails(),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _drawingGroups.length,
        itemBuilder: (context, index) {
          final group = _drawingGroups[index];
          return _buildGroupTile(group);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final groupIndex = _drawingGroups.indexWhere((g) => g.groupName == 'Prescription');
          final group = groupIndex != -1 
              ? _drawingGroups[groupIndex] 
              : DrawingGroup(id: 'Prescription', groupName: 'Prescription', pages: []);
          _addNewPageToGroup(group);
        },
        label: const Text("Create Prescription"),
        icon: const Icon(Icons.add),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildGroupTile(DrawingGroup group) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        title: Text(group.groupName, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: IconButton(
          icon: Icon(Icons.add_box_rounded, color: primaryBlue),
          onPressed: () => _addNewPageToGroup(group),
        ),
        children: group.pages.map((page) => ListTile(
          title: Text(page.displayName),
          subtitle: Text("Page ${page.pageNumber}"),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CanvasDrawingPage(
                  opdId: widget.opdId,
                  uhid: widget.uhid,
                  groupId: group.groupName,
                  pageId: page.id,
                  groupName: group.groupName,
                ),
              ),
            ).then((_) => _loadAllDetails(isBackgroundRefresh: true));
          },
        )).toList(),
      ),
    );
  }



  void _addNewPageToGroup(DrawingGroup group) {
    final config = findGroupConfigByName(group.groupName);
    if (config == null) return;

    // Logic for existing groups
    if (config.behavior == AddBehavior.singlePageOnly && group.pages.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("This group can only contain one item.")));
      return;
    }

    if (config.behavior == AddBehavior.singlePairOnly && group.pages.isNotEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("This group already has a pair.")));
       return;
    }

    if (config.behavior == AddBehavior.singlePairOnly || config.behavior == AddBehavior.multiPagePaired) {
       _addPairedPages(group, config.templateTag!, config.pageNamePrefix);
    } else {
       _addSinglePage(group, config.templateTag!, config.pageNamePrefix);
    }
  }

  void _addPairedPages(DrawingGroup group, String tag, String prefix) {
    final template = _availableTemplates.firstWhere((t) => t.tag == tag, orElse: () => _availableTemplates.first);
    
    int maxPageNumber = group.pages.isEmpty ? 0 : group.pages.map((p) => p.pageNumber).reduce(max);
    
    final frontPage = DrawingPage(
        id: generateUniqueId() + "_1",
        templateImageUrl: template.url,
        pageNumber: maxPageNumber + 1,
        pageName: "$prefix (Front)",
        groupName: group.groupName
    );

    final List<DrawingPage> pagesToCreate = [frontPage];

    if (template.url2 != null && template.url2!.isNotEmpty) {
      final backPage = DrawingPage(
          id: generateUniqueId() + "_2",
          templateImageUrl: template.url2!,
          pageNumber: maxPageNumber + 2,
          pageName: "$prefix (Back)",
          groupName: group.groupName
      );
      pagesToCreate.add(backPage);
    }
    
    _createPagesInDb(pagesToCreate);
  }
}
