import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'drawing_models.dart';
import 'supabase_config.dart';

class CanvasDrawingPage extends StatefulWidget {
  final int opdId;
  final String uhid;
  final String groupId;
  final String pageId;
  final String groupName;

  const CanvasDrawingPage({
    super.key,
    required this.opdId,
    required this.uhid,
    required this.groupId,
    required this.pageId,
    required this.groupName,
  });

  @override
  State<CanvasDrawingPage> createState() => _CanvasDrawingPageState();
}

class _CanvasDrawingPageState extends State<CanvasDrawingPage> {
  DrawingPage? _currentPage;
  List<DrawingPage> _groupPages = [];
  int _currentPageIndex = -1;
  bool _isLoading = true;
  Color _currentColor = Colors.black;
  double _strokeWidth = 2.0;
  bool _isErasing = false;

  List<DrawingLine> _lines = [];
  DrawingLine? _currentLine;

  final TransformationController _transformationController = TransformationController();
  final SupabaseClient supabase = SupabaseConfig.client;
  bool _isPenActive = false;

  @override
  void initState() {
    super.initState();
    _loadPageData();
  }

  Future<void> _loadPageData() async {
    try {
      final response = await supabase
          .from('ipd_pages')
          .select()
          .eq('uhid', widget.uhid)
          .eq('group_name', widget.groupName)
          .order('page_number', ascending: true);

      if (mounted) {
        setState(() {
          _groupPages = (response as List).map((r) => DrawingPage.fromRow(r)).toList();
          _currentPageIndex = _groupPages.indexWhere((p) => p.id == widget.pageId);
          if (_currentPageIndex != -1) {
            _currentPage = _groupPages[_currentPageIndex];
            _lines = List.from(_currentPage!.lines);
          } else if (_groupPages.isNotEmpty) {
            _currentPageIndex = 0;
            _currentPage = _groupPages[0];
            _lines = List.from(_currentPage!.lines);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading page: $e");
    }
  }

  Future<void> _savePageData() async {
    if (_currentPage == null) return;
    
    final updatedPage = _currentPage!.copyWith(lines: _lines);
    final row = updatedPage.toRow(widget.opdId, widget.uhid);

    try {
      await supabase.from('ipd_pages').update(row).eq('id', _currentPage!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saved Successfully")));
      }
    } catch (e) {
      debugPrint("Error saving page: $e");
    }
  }

  void _onPointerDown(PointerDownEvent details) {
    if (details.kind != PointerDeviceKind.stylus) return;

    setState(() {
      _isPenActive = true;
      final Offset localPos = details.localPosition;
      
      _currentLine = DrawingLine(
        points: [localPos],
        color: _isErasing ? Colors.black : _currentColor, // Color doesn't matter for destinationOut but black is standard
        width: _isErasing ? 20.0 : _strokeWidth, // Much larger stroke for eraser
        isErased: _isErasing,
      );
    });
  }

  void _onPointerMove(PointerMoveEvent details) {
    if (details.kind != PointerDeviceKind.stylus || _currentLine == null) return;

    setState(() {
      final Offset localPos = details.localPosition;
      _currentLine = _currentLine?.copyWith(
        points: [..._currentLine!.points, localPos],
      );
    });
  }

  void _onPointerUp(PointerUpEvent details) {
    setState(() {
      _isPenActive = false;
      if (_currentLine != null) {
        _lines.add(_currentLine!);
        _currentLine = null;
      }
    });
  }

  Future<void> _switchPage(int newIndex) async {
    if (newIndex < 0 || newIndex >= _groupPages.length) return;
    
    await _savePageData();

    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('ipd_pages')
          .select()
          .eq('id', _groupPages[newIndex].id)
          .single();

      if (mounted) {
        setState(() {
          _currentPage = DrawingPage.fromRow(response);
          _lines = List.from(_currentPage!.lines);
          _currentPageIndex = newIndex;
          _transformationController.value = Matrix4.identity();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error switching page: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Uint8List?> _renderLinesToPng(List<DrawingLine> lines) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = const Size(1000, 1414);

    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    
    for (var line in lines) {
      final paint = Paint()
        ..color = line.color
        ..strokeWidth = line.width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      if (line.isErased) {
        paint.blendMode = BlendMode.dstOut;
      }

      if (line.points.length > 1) {
        for (int i = 0; i < line.points.length - 1; i++) {
          canvas.drawLine(line.points[i], line.points[i + 1], paint);
        }
      }
    }
    canvas.restore();

    final picture = recorder.endRecording();
    final img = await picture.toImage(1000, 1414);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _printGroupPdf() async {
    await _savePageData();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Preparing PDF...")));

    try {
      final doc = pw.Document();

      final response = await supabase
          .from('ipd_pages')
          .select()
          .eq('uhid', widget.uhid)
          .eq('group_name', widget.groupName)
          .order('page_number', ascending: true);

      final pages = (response as List).map((r) => DrawingPage.fromRow(r)).toList();

      for (var page in pages) {
        pw.ImageProvider? bgImage;
        if (page.templateImageUrl.isNotEmpty) {
          try {
            bgImage = await networkImage(page.templateImageUrl);
          } catch (e) {
            debugPrint("Failed to load bg image for pdf: $e");
          }
        }

        final linesPng = await _renderLinesToPng(page.lines);

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (pw.Context context) {
              return pw.Stack(
                children: [
                  if (bgImage != null)
                    pw.Positioned.fill(
                      child: pw.Image(bgImage, fit: pw.BoxFit.fill),
                    ),
                  if (linesPng != null)
                    pw.Positioned.fill(
                      child: pw.Image(pw.MemoryImage(linesPng), fit: pw.BoxFit.fill),
                    ),
                ],
              );
            },
          ),
        );
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: '${widget.uhid}_${widget.groupName}.pdf',
      );
    } catch (e) {
      debugPrint("PDF generation error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error generating PDF: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFE2E8F0),
      appBar: AppBar(
        title: Text('${widget.groupName} (${_currentPageIndex + 1}/${_groupPages.length})', style: const TextStyle(fontSize: 16)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          if (_currentPageIndex > 0)
            IconButton(
              icon: const Icon(Icons.arrow_upward),
              tooltip: "Previous Page",
              onPressed: () => _switchPage(_currentPageIndex - 1),
            ),
          if (_currentPageIndex < _groupPages.length - 1)
            IconButton(
              icon: const Icon(Icons.arrow_downward),
              tooltip: "Next Page",
              onPressed: () => _switchPage(_currentPageIndex + 1),
            ),
          const VerticalDivider(width: 1, indent: 10, endIndent: 10),
          // Color Selector
          ...[
            Colors.black, 
            Colors.red, 
            Colors.blue, 
            Colors.green, 
            Colors.orange, 
            Colors.purple, 
            Colors.brown
          ].map((color) => 
            IconButton(
              icon: Icon(Icons.circle, color: color, size: _currentColor == color && !_isErasing ? 30 : 20),
              onPressed: () => setState(() {
                _currentColor = color;
                _isErasing = false;
              }),
            )
          ),
          const VerticalDivider(width: 1, indent: 10, endIndent: 10),
          IconButton(
            icon: Icon(Icons.cleaning_services, color: _isErasing ? Colors.red : Colors.blue),
            tooltip: "Eraser (Touch to Erase Middle)",
            onPressed: () => setState(() => _isErasing = true),
          ),
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: "Undo Last Action",
            onPressed: () {
              if (_lines.isNotEmpty) {
                setState(() => _lines.removeLast());
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: "Clear All",
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Clear Canvas"),
                  content: const Text("Are you sure you want to delete everything?"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("No")),
                    TextButton(onPressed: () {
                      setState(() => _lines.clear());
                      Navigator.pop(ctx);
                    }, child: const Text("Yes")),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: "Save",
            onPressed: _savePageData,
          ),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: "Print/Download PDF",
            onPressed: _printGroupPdf,
          ),
        ],
      ),
      body: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 0.1,
        maxScale: 5.0,
        panEnabled: !_isPenActive,
        scaleEnabled: !_isPenActive,
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              child: Container(
                width: 1000, // Fixed virtual size for consistent drawing
                height: 1414, // A4 aspect ratio
                color: Colors.white,
                child: Stack(
                  children: [
                    // Background Template
                    if (_currentPage?.templateImageUrl.isNotEmpty ?? false)
                      Positioned.fill(
                        child: Image.network(
                          _currentPage!.templateImageUrl,
                          fit: BoxFit.fill,
                          errorBuilder: (ctx, err, stack) => const Center(child: Text("Template Load Failed")),
                        ),
                      ),
                    
                    // Drawing Overlay
                    Positioned.fill(
                      child: CustomPaint(
                        painter: DrawingPainter(lines: _lines, currentLine: _currentLine),
                        size: Size.infinite,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<DrawingLine> lines;
  final DrawingLine? currentLine;

  DrawingPainter({required this.lines, this.currentLine});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    
    for (var line in lines) {
      _drawLine(canvas, line);
    }
    if (currentLine != null) {
      _drawLine(canvas, currentLine!);
    }
    
    canvas.restore();
  }

  void _drawLine(Canvas canvas, DrawingLine line) {
    final paint = Paint()
      ..color = line.color
      ..strokeWidth = line.width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (line.isErased) {
      paint.blendMode = BlendMode.dstOut;
    }

    if (line.points.length > 1) {
      for (int i = 0; i < line.points.length - 1; i++) {
        canvas.drawLine(line.points[i], line.points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
