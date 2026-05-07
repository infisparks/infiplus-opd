import 'package:flutter/material.dart';
import 'dart:convert';

class DrawingGroup {
  final String id;
  final String groupName;
  final List<DrawingPage> pages;

  DrawingGroup({
    required this.id,
    required this.groupName,
    required this.pages,
  });

  DrawingGroup copyWith({
    String? id,
    String? groupName,
    List<DrawingPage>? pages,
  }) {
    return DrawingGroup(
      id: id ?? this.id,
      groupName: groupName ?? this.groupName,
      pages: pages ?? this.pages,
    );
  }

  factory DrawingGroup.fromJson(Map<String, dynamic> json) {
    return DrawingGroup(
      id: json['id'] ?? '',
      groupName: json['group_name'] ?? '',
      pages: (json['pages'] as List? ?? [])
          .map((e) => DrawingPage.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'group_name': groupName,
        'pages': pages.map((e) => e.toJson()).toList(),
      };
}

class DrawingPage {
  final String id;
  final String pageName;
  final int pageNumber;
  final String groupName;
  final String templateImageUrl;
  final List<DrawingLine> lines;
  final List<DrawingImage> images;
  final List<DrawingText> texts;
  final bool isDeleted;
  final String? locationTag;
  final String? updatedAt;

  DrawingPage({
    required this.id,
    required this.pageName,
    required this.pageNumber,
    required this.groupName,
    required this.templateImageUrl,
    this.lines = const [],
    this.images = const [],
    this.texts = const [],
    this.isDeleted = false,
    this.locationTag,
    this.updatedAt,
  });

  String get displayName => pageName;

  DrawingPage copyWith({
    String? id,
    String? pageName,
    int? pageNumber,
    String? groupName,
    String? templateImageUrl,
    List<DrawingLine>? lines,
    List<DrawingImage>? images,
    List<DrawingText>? texts,
    bool? isDeleted,
    String? locationTag,
    bool clearLocationTag = false,
    String? updatedAt,
  }) {
    return DrawingPage(
      id: id ?? this.id,
      pageName: pageName ?? this.pageName,
      pageNumber: pageNumber ?? this.pageNumber,
      groupName: groupName ?? this.groupName,
      templateImageUrl: templateImageUrl ?? this.templateImageUrl,
      lines: lines ?? this.lines,
      images: images ?? this.images,
      texts: texts ?? this.texts,
      isDeleted: isDeleted ?? this.isDeleted,
      locationTag: clearLocationTag ? null : (locationTag ?? this.locationTag),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory DrawingPage.fromRow(Map<String, dynamic> row) {
    dynamic canvasData = row['canvas_data'];
    if (canvasData is String) {
      canvasData = jsonDecode(canvasData);
    } else if (canvasData == null) {
      canvasData = {};
    }
    return DrawingPage(
      id: row['id']?.toString() ?? '',
      pageName: row['page_name'] ?? '',
      pageNumber: row['page_number'] ?? 0,
      groupName: row['group_name'] ?? '',
      templateImageUrl: row['template_image_url'] ?? '',
      isDeleted: row['is_deleted'] ?? false,
      locationTag: row['location_tag'],
      updatedAt: row['updated_at'],
      lines: (canvasData['lines'] as List? ?? [])
          .map((e) => DrawingLine.fromJson(e))
          .toList(),
      images: (canvasData['images'] as List? ?? [])
          .map((e) => DrawingImage.fromJson(e))
          .toList(),
      texts: (canvasData['texts'] as List? ?? [])
          .map((e) => DrawingText.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toRow(int ipdId, String uhid, {bool includeCanvasData = true}) {
    final row = {
      'id': id,
      'ipd_id': ipdId,
      'uhid': uhid,
      'group_name': groupName,
      'page_name': pageName,
      'page_number': pageNumber,
      'template_image_url': templateImageUrl,
      'is_deleted': isDeleted,
      'location_tag': locationTag,
    };
    if (includeCanvasData) {
      row['canvas_data'] = {
        'lines': lines.map((e) => e.toJson()).toList(),
        'images': images.map((e) => e.toJson()).toList(),
        'texts': texts.map((e) => e.toJson()).toList(),
      };
    }
    return row;
  }

  factory DrawingPage.fromJson(Map<String, dynamic> json) {
    return DrawingPage(
      id: json['id'] ?? '',
      pageName: json['page_name'] ?? '',
      pageNumber: json['page_number'] ?? 0,
      groupName: json['group_name'] ?? '',
      templateImageUrl: json['template_image_url'] ?? '',
      lines: (json['lines'] as List? ?? [])
          .map((e) => DrawingLine.fromJson(e))
          .toList(),
      images: (json['images'] as List? ?? [])
          .map((e) => DrawingImage.fromJson(e))
          .toList(),
      texts: (json['texts'] as List? ?? [])
          .map((e) => DrawingText.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'page_name': pageName,
        'page_number': pageNumber,
        'group_name': groupName,
        'template_image_url': templateImageUrl,
        'lines': lines.map((e) => e.toJson()).toList(),
        'images': images.map((e) => e.toJson()).toList(),
        'texts': texts.map((e) => e.toJson()).toList(),
      };
}

class DrawingLine {
  final List<Offset> points;
  final Color color;
  final double width;
  final bool isErased;

  DrawingLine({
    required this.points,
    required this.color,
    required this.width,
    this.isErased = false,
  });

  DrawingLine copyWith({
    List<Offset>? points,
    Color? color,
    double? width,
    bool? isErased,
  }) {
    return DrawingLine(
      points: points ?? this.points,
      color: color ?? this.color,
      width: width ?? this.width,
      isErased: isErased ?? this.isErased,
    );
  }

  factory DrawingLine.fromJson(Map<String, dynamic> json) {
    return DrawingLine(
      points: (json['points'] as List? ?? [])
          .map((e) => Offset(e['x'], e['y']))
          .toList(),
      color: Color(json['color']),
      width: json['width'].toDouble(),
      isErased: json['is_erased'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'points': points.map((e) => {'x': e.dx, 'y': e.dy}).toList(),
        'color': color.value,
        'width': width,
        'is_erased': isErased,
      };
}

class DrawingImage {
  final String id;
  final String imageUrl;
  final Offset position;
  final double scale;
  final bool isErased;

  DrawingImage({
    required this.id,
    required this.imageUrl,
    required this.position,
    this.scale = 1.0,
    this.isErased = false,
  });

  DrawingImage copyWith({
    String? id,
    String? imageUrl,
    Offset? position,
    double? scale,
    bool? isErased,
  }) {
    return DrawingImage(
      id: id ?? this.id,
      imageUrl: imageUrl ?? this.imageUrl,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      isErased: isErased ?? this.isErased,
    );
  }

  factory DrawingImage.fromJson(Map<String, dynamic> json) {
    return DrawingImage(
      id: json['id'] ?? '',
      imageUrl: json['image_url'] ?? '',
      position: Offset(json['x'], json['y']),
      scale: json['scale']?.toDouble() ?? 1.0,
      isErased: json['is_erased'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'image_url': imageUrl,
        'x': position.dx,
        'y': position.dy,
        'scale': scale,
        'is_erased': isErased,
      };
}

class DrawingText {
  final String id;
  final String text;
  final Offset position;
  final int colorValue;
  final double fontSize;
  final bool isErased;
  final String? createdByEmail;

  DrawingText({
    required this.id,
    required this.text,
    required this.position,
    required this.colorValue,
    required this.fontSize,
    this.isErased = false,
    this.createdByEmail,
  });

  DrawingText copyWith({
    String? id,
    String? text,
    Offset? position,
    int? colorValue,
    double? fontSize,
    bool? isErased,
    String? createdByEmail,
  }) {
    return DrawingText(
      id: id ?? this.id,
      text: text ?? this.text,
      position: position ?? this.position,
      colorValue: colorValue ?? this.colorValue,
      fontSize: fontSize ?? this.fontSize,
      isErased: isErased ?? this.isErased,
      createdByEmail: createdByEmail ?? this.createdByEmail,
    );
  }

  factory DrawingText.fromJson(Map<String, dynamic> json) {
    return DrawingText(
      id: json['id'] ?? '',
      text: json['text'] ?? '',
      position: Offset(json['x'], json['y']),
      colorValue: json['color_value'],
      fontSize: json['font_size']?.toDouble() ?? 16.0,
      isErased: json['is_erased'] ?? false,
      createdByEmail: json['created_by_email'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'x': position.dx,
        'y': position.dy,
        'color_value': colorValue,
        'font_size': fontSize,
        'is_erased': isErased,
        'created_by_email': createdByEmail,
      };
}

String generateUniqueId() {
  return DateTime.now().millisecondsSinceEpoch.toString();
}
