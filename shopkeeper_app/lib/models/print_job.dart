class PrintJob {
  final dynamic id; // Can be int (file ID) or order_group_id
  final String customerName;
  final String filename;
  final int numPages;
  final int copies;
  final String printMode;
  final String colorMode;
  final String paperSize;
  final double totalCost;
  final int? queuePosition;
  final String createdAt;
  final String? comment;
  
  // Order group fields (for batch uploads)
  final int? fileCount;
  final int? totalPages;
  final dynamic orderGroupId;
  /// File ID to use for cancel/print-started (any file in the order).
  final int? firstFileId;
  /// Backend file status: "uploaded" or "printing" (e.g. stuck after app crash).
  final String? fileStatus;

  PrintJob({
    required this.id,
    required this.customerName,
    required this.filename,
    required this.numPages,
    required this.copies,
    required this.printMode,
    required this.colorMode,
    required this.paperSize,
    required this.totalCost,
    this.queuePosition,
    required this.createdAt,
    this.comment,
    this.fileCount,
    this.totalPages,
    this.orderGroupId,
    this.firstFileId,
    this.fileStatus,
  });

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  factory PrintJob.fromJson(Map<String, dynamic> json) {
    // Check if this is an order group (has file_count)
    final isOrderGroup = json['file_count'] != null;
    
    return PrintJob(
      id: isOrderGroup ? json['order_group_id'] : json['id'],
      customerName: '${json['customer_name'] ?? 'Unknown'}',
      filename: isOrderGroup 
          ? '${json['file_count']} file(s)' 
          : '${json['filename'] ?? 'Unknown'}',
      numPages: isOrderGroup ? _toInt(json['total_pages']) : _toInt(json['num_pages']),
      copies: _toInt(json['copies']).clamp(1, 999),
      printMode: json['print_mode'] ?? 'single',
      colorMode: json['color_mode'] ?? 'bw',
      paperSize: json['paper_size'] ?? 'A4',
      totalCost: (json['total_cost'] ?? 0).toDouble(),
      queuePosition: json['queue_position'],
      createdAt: json['created_at'] ?? '',
      comment: json['comment'],
      fileCount: json['file_count'],
      totalPages: json['total_pages'],
      orderGroupId: json['order_group_id'],
      firstFileId: json['first_file_id'] != null ? _toInt(json['first_file_id']) : (isOrderGroup ? null : _toInt(json['id'])),
      fileStatus: json['status'] as String?,
    );
  }
  
  bool get isBatchOrder => (fileCount ?? 0) > 1;
  
  /// File ID to pass to cancel or print-started API.
  int get fileIdForApi => firstFileId ?? _toInt(id);
}
