import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:pdf_combiner/models/merge_input.dart';
import 'package:pdf_combiner/pdf_combiner.dart';
import '../models/print_job.dart';

/// Utility class for PDF operations including front page generation and merging
class PdfUtils {
  /// Creates a front page PDF with customer details, shop info, and print options
  static Future<Uint8List> createFrontPage({
    required PrintJob job,
    required String shopName,
    String companyName = 'QPrint Service',
  }) async {
    final pdf = pw.Document();
    final pageFormat = _getPageFormat(job.paperSize);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header with branding
              pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 20),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(width: 2, color: PdfColors.grey700),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      companyName,
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      shopName,
                      style: pw.TextStyle(
                        fontSize: 18,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 30),

              // Customer Information Section
              pw.Text(
                'CUSTOMER INFORMATION',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey800,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                children: [
                  pw.Text('Customer:', style: _labelStyle),
                  pw.SizedBox(width: 10),
                  pw.Text(
                    job.customerName,
                    style: _valueStyle,
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                children: [
                  pw.Text('Date:', style: _labelStyle),
                  pw.SizedBox(width: 10),
                  pw.Text(
                    _formatDate(job.createdAt),
                    style: _valueStyle,
                  ),
                ],
              ),

              pw.SizedBox(height: 30),

              // Print Job Details Section
              pw.Text(
                'PRINT JOB DETAILS',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey800,
                ),
              ),
              pw.SizedBox(height: 12),
              // For batch orders, show file count instead of single filename
              if (job.isBatchOrder && (job.fileCount ?? 0) > 1) ...[
                _buildDetailRow('Files:', '${job.fileCount} files'),
                pw.SizedBox(height: 8),
                _buildDetailRow('Total Pages:', job.totalPages?.toString() ?? job.numPages.toString()),
              ] else ...[
                _buildDetailRow('Filename:', job.filename),
                pw.SizedBox(height: 8),
                _buildDetailRow('Pages:', job.numPages.toString()),
              ],
              pw.SizedBox(height: 8),
              _buildDetailRow('Copies:', job.copies.toString()),
              pw.SizedBox(height: 8),
              _buildDetailRow('Print Mode:', _formatPrintMode(job.printMode)),
              pw.SizedBox(height: 8),
              _buildDetailRow('Color Mode:', _formatColorMode(job.colorMode)),
              pw.SizedBox(height: 8),
              _buildDetailRow('Paper Size:', job.paperSize.toUpperCase()),

              // Comment if available
              if (job.comment != null && job.comment!.isNotEmpty) ...[
                pw.SizedBox(height: 30),
                pw.Text(
                  'COMMENT',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey800,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    job.comment ?? '',
                    style: _valueStyle,
                  ),
                ),
              ],

              // Spacer to push footer down
              pw.Spacer(),

              // Footer with cost
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Total Cost:',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      '₹${job.totalCost.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Merges the front page PDF with the original PDF file
  /// Returns the merged PDF as bytes
  static Future<Uint8List> mergePdfs({
    required Uint8List frontPageBytes,
    required String originalFilePath,
  }) async {
    final originalFile = File(originalFilePath);
    if (!await originalFile.exists()) {
      throw Exception('Original PDF not found: $originalFilePath');
    }

    final tempDir = Directory.systemTemp;
    final outputPath =
        '${tempDir.path}${Platform.pathSeparator}merged_${DateTime.now().millisecondsSinceEpoch}.pdf';

    try {
      await PdfCombiner.mergeMultiplePDFs(
        inputs: [
          MergeInput.bytes(frontPageBytes),
          MergeInput.path(originalFilePath),
        ],
        outputPath: outputPath,
      );
      final mergedBytes = await File(outputPath).readAsBytes();
      return mergedBytes;
    } finally {
      try {
        final f = File(outputPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Merges front page (once) with document PDF (repeated N times for copies)
  /// Returns the merged PDF as bytes
  /// This ensures the front page is printed only once per batch, regardless of copies
  static Future<Uint8List> mergePdfsWithCopies({
    required Uint8List frontPageBytes,
    required String documentFilePath,
    required int copies, // Number of times to repeat the document
  }) async {
    final documentFile = File(documentFilePath);
    if (!await documentFile.exists()) {
      throw Exception('Document PDF not found: $documentFilePath');
    }

    final tempDir = Directory.systemTemp;
    final outputPath =
        '${tempDir.path}${Platform.pathSeparator}merged_copies_${DateTime.now().millisecondsSinceEpoch}.pdf';

    try {
      // Build inputs: front page (1x) + document (N times)
      final inputs = <MergeInput>[
        MergeInput.bytes(frontPageBytes), // Front page once
      ];
      
      // Add document N times
      for (int i = 0; i < copies; i++) {
        inputs.add(MergeInput.path(documentFilePath));
      }

      await PdfCombiner.mergeMultiplePDFs(
        inputs: inputs,
        outputPath: outputPath,
      );
      
      final mergedBytes = await File(outputPath).readAsBytes();
      return mergedBytes;
    } finally {
      try {
        final f = File(outputPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Merges multiple PDF files into a single PDF
  /// Returns the merged PDF as bytes
  static Future<Uint8List> mergeMultiplePdfs({
    required List<String> pdfFilePaths,
  }) async {
    if (pdfFilePaths.isEmpty) {
      throw Exception('No PDF files provided for merging');
    }

    final inputs = <MergeInput>[];
    for (final filePath in pdfFilePaths) {
      final file = File(filePath);
      if (!await file.exists()) {
        if (kDebugMode) print('⚠️ Warning: File not found: $filePath');
        continue;
      }
      inputs.add(MergeInput.path(filePath));
    }

    if (inputs.isEmpty) {
      throw Exception('No PDF files were found for merging');
    }

    final tempDir = Directory.systemTemp;
    final outputPath =
        '${tempDir.path}${Platform.pathSeparator}merged_multi_${DateTime.now().millisecondsSinceEpoch}.pdf';

    try {
      await PdfCombiner.mergeMultiplePDFs(
        inputs: inputs,
        outputPath: outputPath,
      );
      final mergedBytes = await File(outputPath).readAsBytes();
      return mergedBytes;
    } finally {
      try {
        final f = File(outputPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Helper method to build a detail row
  static pw.Widget _buildDetailRow(String label, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 100,
          child: pw.Text(label, style: _labelStyle),
        ),
        pw.Expanded(
          child: pw.Text(value, style: _valueStyle),
        ),
      ],
    );
  }

  /// Label text style
  static final _labelStyle = pw.TextStyle(
    fontSize: 12,
    color: PdfColors.grey700,
  );

  /// Value text style
  static final _valueStyle = pw.TextStyle(
    fontSize: 12,
    color: PdfColors.black,
  );

  /// Format date string
  static String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('yyyy-MM-dd HH:mm').format(date);
    } catch (e) {
      return dateString;
    }
  }

  /// Format print mode
  static String _formatPrintMode(String mode) {
    return mode.toLowerCase() == 'double' ? 'Double-sided' : 'Single-sided';
  }

  /// Format color mode
  static String _formatColorMode(String mode) {
    return mode.toLowerCase() == 'color' ? 'Color' : 'Black & White';
  }

  /// Get page format from paper size string
  static PdfPageFormat _getPageFormat(String paperSize) {
    switch (paperSize.toUpperCase()) {
      case 'A4':
        return PdfPageFormat.a4;
      case 'LETTER':
        return PdfPageFormat.letter;
      case 'LEGAL':
        return PdfPageFormat.legal;
      case 'A3':
        return PdfPageFormat.a3;
      case 'A5':
        return PdfPageFormat.a5;
      default:
        return PdfPageFormat.a4;
    }
  }
}
