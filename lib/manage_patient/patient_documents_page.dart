import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart'; // For AppColors
import 'document_viewer_page.dart';

class PatientDocumentsPage extends StatefulWidget {
  final String uhid;
  final int opdId;

  const PatientDocumentsPage({super.key, required this.uhid, required this.opdId});

  @override
  State<PatientDocumentsPage> createState() => _PatientDocumentsPageState();
}

class _PatientDocumentsPageState extends State<PatientDocumentsPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _documents = [];
  bool _isLoading = true;
  String? _selectedFolder;

  @override
  void initState() {
    super.initState();
    _fetchDocuments();
  }

  Future<void> _fetchDocuments() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('patient_documents')
          .select()
          .eq('uhid', widget.uhid)
          .order('created_at', ascending: false);
      setState(() {
        _documents = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint("Error fetching documents: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, List<Map<String, dynamic>>> get _groupedDocuments {
    final map = <String, List<Map<String, dynamic>>>{};
    for (var doc in _documents) {
      final group = doc['document_group'] ?? 'Other';
      map.putIfAbsent(group, () => []).add(doc);
    }
    return map;
  }

  void _openDocument(List<Map<String, dynamic>> folderDocs, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DocumentViewerPage(
          documents: folderDocs,
          initialIndex: index,
        ),
      ),
    );
  }

  void _showUploadOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.blue),
                title: const Text('Take a Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUpload(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.purple),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUpload(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('Upload PDF/Document'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFile();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source, imageQuality: 80);
    if (image != null) {
      _showUploadDialog(File(image.path));
    }
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png', 'jpeg'],
    );
    if (result != null && result.files.single.path != null) {
      _showUploadDialog(File(result.files.single.path!));
    }
  }

  void _showUploadDialog(File file) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UploadDetailsDialog(
        uhid: widget.uhid,
        opdId: widget.opdId,
        file: file,
        onSuccess: () {
          _fetchDocuments();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupedDocs = _groupedDocuments;

    return Scaffold(
      backgroundColor: AppColors.bgBody,
      appBar: AppBar(
        title: Text(
          _selectedFolder == null ? 'Patient Documents' : _selectedFolder!,
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color: AppColors.textPrimary,
          onPressed: () {
            if (_selectedFolder != null) {
              setState(() => _selectedFolder = null);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _selectedFolder == null
              ? _buildFoldersGrid(groupedDocs)
              : _buildDocumentsList(groupedDocs[_selectedFolder] ?? []),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showUploadOptions,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text("Upload", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildFoldersGrid(Map<String, List<Map<String, dynamic>>> groupedDocs) {
    if (groupedDocs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text("No folders yet.", style: GoogleFonts.poppins(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    final folderNames = groupedDocs.keys.toList();
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180, // Responsive folder size
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.1,
      ),
      itemCount: folderNames.length,
      itemBuilder: (context, index) {
        final folder = folderNames[index];
        final count = groupedDocs[folder]!.length;
        return GestureDetector(
          onTap: () => setState(() => _selectedFolder = folder),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.folder, size: 48, color: Colors.amber),
                  const Spacer(),
                  Text(folder, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text("$count files", style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDocumentsList(List<Map<String, dynamic>> folderDocs) {
    if (folderDocs.isEmpty) {
      return Center(child: Text("Folder is empty.", style: GoogleFonts.poppins()));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: folderDocs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final doc = folderDocs[index];
        final isPdf = doc['file_url'].toString().toLowerCase().contains('.pdf');
        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isPdf ? Colors.red.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isPdf ? Icons.picture_as_pdf : Icons.image,
                color: isPdf ? Colors.red : Colors.blue,
              ),
            ),
            title: Text(doc['document_name'], style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(
              doc['created_at'].toString().substring(0, 10),
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
            ),
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            onTap: () => _openDocument(folderDocs, index),
          ),
        );
      },
    );
  }
}

class UploadDetailsDialog extends StatefulWidget {
  final String uhid;
  final int opdId;
  final File file;
  final VoidCallback onSuccess;

  const UploadDetailsDialog({super.key, required this.uhid, required this.opdId, required this.file, required this.onSuccess});

  @override
  State<UploadDetailsDialog> createState() => _UploadDetailsDialogState();
}

class _UploadDetailsDialogState extends State<UploadDetailsDialog> {
  TextEditingController? _autocompleteController;
  String _selectedGroup = 'Lab Report';
  final List<String> _groups = ['Lab Report', 'Radiology', 'Prescription', 'Other'];
  bool _isUploading = false;
  
  List<String> _savedDocumentNames = [];
  bool _isLoadingNames = true;

  @override
  void initState() {
    super.initState();
    _fetchSavedNames();
  }

  Future<void> _fetchSavedNames() async {
    try {
      final response = await Supabase.instance.client
          .from('config_data')
          .select('data')
          .eq('data_heading', 'document_names')
          .maybeSingle();

      if (response != null && response['data'] != null) {
        setState(() {
          _savedDocumentNames = List<String>.from(response['data']);
        });
      }
    } catch (e) {
      debugPrint("Error loading names: $e");
    } finally {
      if (mounted) setState(() => _isLoadingNames = false);
    }
  }

  Future<void> _saveNewNameIfNeeded(String name) async {
    if (_savedDocumentNames.contains(name)) return;
    
    final updatedList = List<String>.from(_savedDocumentNames)..add(name);
    try {
      await Supabase.instance.client.from('config_data').upsert({
        'data_heading': 'document_names',
        'data': updatedList,
      }, onConflict: 'data_heading');
    } catch (e) {
      debugPrint("Error saving new name: $e");
    }
  }

  Future<void> _uploadDocument() async {
    final docName = _autocompleteController?.text.trim() ?? '';
    if (docName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please provide a document name')));
      return;
    }

    setState(() => _isUploading = true);

    try {
      await _saveNewNameIfNeeded(docName);

      final supabase = Supabase.instance.client;
      final fileExtension = widget.file.path.split('.').last;
      final fileName = '${widget.uhid}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final filePath = '${widget.uhid}/$fileName';

      await supabase.storage.from('patient_documents').upload(
        filePath,
        widget.file,
        fileOptions: const FileOptions(upsert: true),
      );

      final publicUrl = supabase.storage.from('patient_documents').getPublicUrl(filePath);

      await supabase.from('patient_documents').insert({
        'uhid': widget.uhid,
        'opd_id': widget.opdId,
        'document_name': docName,
        'document_group': _selectedGroup,
        'file_url': publicUrl,
      });

      if (mounted) {
        Navigator.pop(context); // Close dialog
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document uploaded successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error uploading: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Upload Details', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoadingNames)
              const LinearProgressIndicator(),
            if (!_isLoadingNames)
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return _savedDocumentNames;
                  }
                  return _savedDocumentNames.where((String option) {
                    return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                  });
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  _autocompleteController = controller;
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Document Name',
                      border: OutlineInputBorder(),
                      hintText: 'Type new or select from list',
                    ),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4.0,
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.6,
                        height: 200,
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: options.length,
                          itemBuilder: (BuildContext context, int index) {
                            final String option = options.elementAt(index);
                            return ListTile(
                              title: Text(option, style: GoogleFonts.poppins()),
                              onTap: () => onSelected(option),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
            initialValue: _selectedGroup,
            decoration: const InputDecoration(
              labelText: 'Document Group',
              border: OutlineInputBorder(),
            ),
            items: _groups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedGroup = val);
            },
          ),
        ],
      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _uploadDocument,
          child: _isUploading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Confirm Upload'),
        ),
      ],
    );
  }
}
