import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import 'widgets/shop_selection_widget.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _selectedFile;
  int _copies = 1;
  String _printMode = 'single';
  String _colorMode = 'bw';
  String _paperSize = 'A4';
  String _printType = 'private';
  int? _selectedShopId;
  String _comment = '';
  bool _isUploading = false;
  String? _errorMessage;
  String? _successMessage;
  String? _uniqueCode;
  int? _queuePosition;

  final _apiService = ApiService();
  final _locationService = LocationService();
  double? _userLat;
  double? _userLong;
  List<dynamic> _shops = [];

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    try {
      final position = await _locationService.getCurrentPosition();
      setState(() {
        _userLat = position.latitude;
        _userLong = position.longitude;
      });
      _loadShops();
    } catch (e) {
      // Location not available, still try to load shops
      _loadShops();
    }
  }

  Future<void> _loadShops() async {
    if (_userLat == null || _userLong == null) return;

    try {
      final shops = await _apiService.getShops(_userLat!, _userLong!);
      setState(() {
        _shops = shops;
      });
    } catch (e) {
      // Error loading shops
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx', 'ppt', 'pptx'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to pick file: $e';
      });
    }
  }

  Future<void> _handleUpload() async {
    if (_selectedFile == null) {
      setState(() {
        _errorMessage = 'Please select a file';
      });
      return;
    }

    if (_printType == 'queue' && _selectedShopId == null) {
      setState(() {
        _errorMessage = 'Please select a shop for queue print';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final result = await _apiService.uploadFile(
        filePath: _selectedFile!.path,
        copies: _copies,
        printMode: _printMode,
        colorMode: _colorMode,
        paperSize: _paperSize,
        printType: _printType,
        shopId: _printType == 'queue' ? _selectedShopId : null,
        comment: _comment.isNotEmpty ? _comment : null,
      );

      setState(() {
        _isUploading = false;
        _successMessage = 'File uploaded successfully!';
        _uniqueCode = result['code'];
        _queuePosition = result['queue_position'];
        
        // Reset form
        _selectedFile = null;
        _copies = 1;
        _printMode = 'single';
        _colorMode = 'bw';
        _paperSize = 'A4';
        _printType = 'private';
        _selectedShopId = null;
        _comment = '';
      });

      // Show success dialog
      _showSuccessDialog();
    } catch (e) {
      setState(() {
        _isUploading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.white10,
        title: const Text('Upload Successful!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_printType == 'private' && _uniqueCode != null) ...[
              const Text('Your unique code:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.pink500.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _uniqueCode!,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.pink400,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Share this code with the shopkeeper to print.'),
            ] else if (_printType == 'queue' && _queuePosition != null) ...[
              Text('Your file is in queue position #$_queuePosition'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Upload Section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white10,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.white20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.upload, size: 32, color: AppColors.white),
                    SizedBox(width: 12),
                    Text(
                      'Upload Document',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // File Picker
                ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.file_upload),
                  label: Text(_selectedFile == null
                      ? 'Select File (PDF, images, Word, or PowerPoint)'
                      : _selectedFile!.path.split('/').last),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: AppColors.white20,
                    foregroundColor: AppColors.white,
                  ),
                ),
                if (_selectedFile != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Selected: ${_selectedFile!.path.split('/').last}',
                    style: const TextStyle(
                      color: AppColors.purple200,
                      fontSize: 12,
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Print Settings
                const Text(
                  'Print Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 16),

                // Copies
                Row(
                  children: [
                    const Expanded(
                      child: Text('Copies:', style: TextStyle(color: AppColors.white)),
                    ),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.all(12),
                        ),
                        controller: TextEditingController(text: _copies.toString())
                          ..selection = TextSelection.collapsed(offset: _copies.toString().length),
                        onChanged: (value) {
                          final copies = int.tryParse(value) ?? 1;
                          setState(() {
                            _copies = copies.clamp(1, 100);
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Print Mode
                DropdownButtonFormField<String>(
                  value: _printMode,
                  decoration: const InputDecoration(
                    labelText: 'Print Mode',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'single', child: Text('Single-sided')),
                    DropdownMenuItem(value: 'double', child: Text('Double-sided')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _printMode = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Color Mode
                DropdownButtonFormField<String>(
                  value: _colorMode,
                  decoration: const InputDecoration(
                    labelText: 'Color',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'bw', child: Text('Black & White')),
                    DropdownMenuItem(value: 'color', child: Text('Color')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _colorMode = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Paper Size
                DropdownButtonFormField<String>(
                  value: _paperSize,
                  decoration: const InputDecoration(
                    labelText: 'Paper Size',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'A4', child: Text('A4')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _paperSize = value!;
                    });
                  },
                ),
                const SizedBox(height: 24),

                // Print Type
                const Text(
                  'Print Type',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _printType = 'private';
                            _selectedShopId = null;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _printType == 'private'
                                ? AppColors.pink500.withOpacity(0.3)
                                : AppColors.white10,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _printType == 'private'
                                  ? AppColors.pink400
                                  : AppColors.white20,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.lock, size: 32),
                              const SizedBox(height: 8),
                              const Text(
                                'Private Print',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.white,
                                ),
                              ),
                              const Text(
                                'Get unique code',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.purple200,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _printType = 'queue';
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _printType == 'queue'
                                ? AppColors.pink500.withOpacity(0.3)
                                : AppColors.white10,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _printType == 'queue'
                                  ? AppColors.pink400
                                  : AppColors.white20,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.queue, size: 32),
                              const SizedBox(height: 8),
                              const Text(
                                'Queue Print',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.white,
                                ),
                              ),
                              const Text(
                                'Send to shop',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.purple200,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Shop Selection (for queue prints)
                if (_printType == 'queue') ...[
                  const SizedBox(height: 24),
                  ShopSelectionWidget(
                    shops: _shops,
                    selectedShopId: _selectedShopId,
                    onShopSelected: (shopId) {
                      setState(() {
                        _selectedShopId = shopId;
                      });
                    },
                    onShopsUpdated: _loadShops,
                  ),
                ],

                const SizedBox(height: 24),

                // Comment Field
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Comment (Optional)',
                    hintText: 'Add any special instructions...',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 3,
                  maxLength: 500,
                  onChanged: (value) {
                    setState(() {
                      _comment = value;
                    });
                  },
                ),

                const SizedBox(height: 24),

                // Error/Success Messages
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.red500.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.red300),
                    ),
                  ),
                if (_successMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.green500.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _successMessage!,
                      style: const TextStyle(color: AppColors.green300),
                    ),
                  ),

                const SizedBox(height: 16),

                // Upload Button
                ElevatedButton(
                  onPressed: _isUploading ? null : _handleUpload,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.pink500,
                  ),
                  child: _isUploading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Text(
                          'Upload',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
