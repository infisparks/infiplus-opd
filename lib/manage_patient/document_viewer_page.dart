import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_view/photo_view.dart';

import '../main.dart'; // For AppColors

class DocumentViewerPage extends StatefulWidget {
  final List<Map<String, dynamic>> documents;
  final int initialIndex;

  const DocumentViewerPage({
    super.key,
    required this.documents,
    required this.initialIndex,
  });

  @override
  State<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends State<DocumentViewerPage> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _isImage(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.endsWith('.jpg') || lowerUrl.endsWith('.jpeg') || lowerUrl.endsWith('.png');
  }

  bool _isPdf(String url) {
    return url.toLowerCase().endsWith('.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final currentDoc = widget.documents[_currentIndex];
    
    return Scaffold(
      backgroundColor: AppColors.bgBody,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(currentDoc['document_name'], style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text("${_currentIndex + 1} of ${widget.documents.length} • ${currentDoc['document_group']}", style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          itemCount: widget.documents.length,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          itemBuilder: (context, index) {
            final doc = widget.documents[index];
            final fileUrl = doc['file_url'];
            return Center(
              child: _buildViewer(context, fileUrl),
            );
          },
        ),
      ),
    );
  }

  Widget _buildViewer(BuildContext context, String fileUrl) {
    if (_isImage(fileUrl)) {
      return PhotoView(
        imageProvider: CachedNetworkImageProvider(fileUrl),
        backgroundDecoration: const BoxDecoration(color: Colors.transparent),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 4,
        errorBuilder: (context, error, stackTrace) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text("Failed to load image", style: GoogleFonts.poppins(color: Colors.grey)),
          ],
        ),
      );
    } else if (_isPdf(fileUrl)) {
      return _PdfViewItem(fileUrl: fileUrl);
    } else {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.insert_drive_file, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text("Cannot preview this file type directly.", style: GoogleFonts.poppins(color: Colors.grey)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              final uri = Uri.parse(fileUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.open_in_browser),
            label: const Text("Open Externally"),
          ),
        ],
      );
    }
  }
}

class _PdfViewItem extends StatefulWidget {
  final String fileUrl;

  const _PdfViewItem({required this.fileUrl});

  @override
  State<_PdfViewItem> createState() => _PdfViewItemState();
}

class _PdfViewItemState extends State<_PdfViewItem> {
  final PdfViewerController _pdfViewerController = PdfViewerController();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SfPdfViewer.network(
          widget.fileUrl,
          controller: _pdfViewerController,
          canShowScrollHead: false,
          canShowScrollStatus: false,
          interactionMode: PdfInteractionMode.pan,
          onDocumentLoadFailed: (details) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to load PDF: ${details.description}')),
              );
            }
          },
        ),
        Positioned(
          bottom: 24,
          right: 24,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.zoom_out_rounded, color: Colors.white),
                  tooltip: 'Zoom Out',
                  onPressed: () {
                    _pdfViewerController.zoomLevel = (_pdfViewerController.zoomLevel - 0.5).clamp(1.0, 5.0);
                  },
                ),
                Container(width: 1, height: 24, color: Colors.white.withValues(alpha: 0.3)),
                IconButton(
                  icon: const Icon(Icons.zoom_in_rounded, color: Colors.white),
                  tooltip: 'Zoom In',
                  onPressed: () {
                    _pdfViewerController.zoomLevel = (_pdfViewerController.zoomLevel + 0.5).clamp(1.0, 5.0);
                  },
                ),
                Container(width: 1, height: 24, color: Colors.white.withValues(alpha: 0.3)),
                IconButton(
                  icon: const Icon(Icons.center_focus_strong_rounded, color: Colors.white),
                  tooltip: 'Reset Zoom',
                  onPressed: () {
                    _pdfViewerController.zoomLevel = 1.0;
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
