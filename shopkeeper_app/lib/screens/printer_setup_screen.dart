import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/printer_service.dart';
import 'dashboard_screen.dart';

class PrinterSetupScreen extends StatefulWidget {
  const PrinterSetupScreen({super.key});

  // Static cache for printer name (fallback if SharedPreferences fails)
  static String? _cachedPrinterName;
  
  // Getter for cached printer (accessible from other screens)
  static String? getCachedPrinter() => _cachedPrinterName;
  
  // Setter for cached printer
  static void setCachedPrinter(String? printer) {
    _cachedPrinterName = printer;
  }

  @override
  State<PrinterSetupScreen> createState() => _PrinterSetupScreenState();
}

class _PrinterSetupScreenState extends State<PrinterSetupScreen> {
  final _printerService = PrinterService();
  List<String> _printers = [];
  String? _selectedPrinter;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final printers = await _printerService.getPrinters();
      
      // Try to load saved printer, but don't fail if SharedPreferences doesn't work
      String? savedPrinter;
      try {
        final prefs = await SharedPreferences.getInstance();
        savedPrinter = prefs.getString('default_printer');
      } catch (e) {
        // SharedPreferences not working, continue without saved printer
        if (kDebugMode) print('Warning: Could not load saved printer: $e');
      }

      // Also check memory cache
      String? cachedPrinter = PrinterSetupScreen.getCachedPrinter();
      
      setState(() {
        _printers = printers;
        
        // Try to match saved printer (exact match first)
        if (savedPrinter != null && printers.contains(savedPrinter)) {
          _selectedPrinter = savedPrinter;
          if (kDebugMode) print('DEBUG: Matched saved printer: $savedPrinter');
        }
        // Try to match cached printer (exact match)
        else if (cachedPrinter != null && printers.contains(cachedPrinter)) {
          _selectedPrinter = cachedPrinter;
          if (kDebugMode) print('DEBUG: Matched cached printer: $cachedPrinter');
        }
        // Try lenient matching for saved printer
        else if (savedPrinter != null) {
          final savedLower = savedPrinter.toLowerCase();
          final matched = printers.firstWhere(
            (p) => p.toLowerCase() == savedLower || 
                   p.toLowerCase().contains(savedLower) ||
                   savedLower.contains(p.toLowerCase()),
            orElse: () => '',
          );
          if (matched.isNotEmpty) {
            _selectedPrinter = matched;
            if (kDebugMode) print('DEBUG: Matched saved printer (lenient): $savedPrinter -> $matched');
          }
        }
        // Try lenient matching for cached printer
        else if (cachedPrinter != null) {
          final cachedLower = cachedPrinter.toLowerCase();
          final matched = printers.firstWhere(
            (p) => p.toLowerCase() == cachedLower || 
                   p.toLowerCase().contains(cachedLower) ||
                   cachedLower.contains(p.toLowerCase()),
            orElse: () => '',
          );
          if (matched.isNotEmpty) {
            _selectedPrinter = matched;
            if (kDebugMode) print('DEBUG: Matched cached printer (lenient): $cachedPrinter -> $matched');
          }
        }
        // Default to first printer if available
        else if (printers.isNotEmpty) {
          _selectedPrinter = printers.first;
          if (kDebugMode) print('DEBUG: Using first available printer: ${printers.first}');
        }
        
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load printers: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveAndContinue() async {
    if (_selectedPrinter == null) {
      // Show error if no printer selected
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a printer to continue'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Cache printer name in memory first (always works)
    PrinterSetupScreen.setCachedPrinter(_selectedPrinter);
    if (kDebugMode) print('DEBUG: Cached printer name: $_selectedPrinter');

    // Try to save printer preference to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('default_printer', _selectedPrinter!);
      if (kDebugMode) print('DEBUG: Saved printer to SharedPreferences: $_selectedPrinter');
    } catch (e) {
      // SharedPreferences not working, but we have memory cache
      if (kDebugMode) {
        print('Warning: Could not save printer to SharedPreferences: $e');
        print('DEBUG: Using memory cache for printer: $_selectedPrinter');
      }
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF312E81), Color(0xFF581C87), Color(0xFF9D174D)],
          ),
        ),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.print_rounded, size: 64, color: Colors.white),
                const SizedBox(height: 24),
                const Text(
                  'Select Default Printer',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose the printer to use for all print jobs',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 32),
                
                if (_isLoading)
                  const CircularProgressIndicator(color: Colors.white)
                else if (_errorMessage != null)
                  Column(
                    children: [
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadPrinters,
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                else if (_printers.isEmpty)
                  Column(
                    children: [
                      const Text(
                        'No printers found!',
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please connect a printer and try again.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadPrinters,
                        child: const Text('Refresh List'),
                      ),
                    ],
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedPrinter,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF312E81),
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                        items: _printers.map((printer) {
                          return DropdownMenuItem(
                            value: printer,
                            child: Row(
                              children: [
                                const Icon(Icons.print, color: Colors.white70, size: 20),
                                const SizedBox(width: 12),
                                Text(printer),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedPrinter = value;
                          });
                        },
                      ),
                    ),
                  ),

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _selectedPrinter == null ? null : _saveAndContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedPrinter == null 
                          ? Colors.grey 
                          : Colors.pinkAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _selectedPrinter == null 
                          ? 'Please Select a Printer' 
                          : 'Continue to Dashboard',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (_selectedPrinter == null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orangeAccent, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Printer selection is required to use the app',
                            style: TextStyle(color: Colors.orangeAccent, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
