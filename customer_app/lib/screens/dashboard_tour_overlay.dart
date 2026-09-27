import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';

/// Step content for the dashboard tour.
class DashboardTourStep {
  final String title;
  final String description;

  const DashboardTourStep({
    required this.title,
    required this.description,
  });
}

/// Which target to highlight: null = none (overview), 0-4 = nav items, 5 = app bar.
int? _stepToTargetIndex(int step) {
  if (step == 0) return null;
  if (step >= 1 && step <= 3) return 0; // Upload, Queue, Private -> first tab
  if (step == 4) return 1; // My Files
  if (step == 5) return 2; // Favorites
  if (step == 6) return 3; // Expenses
  if (step == 7) return 4; // Map
  if (step == 8) return 5; // Top bar
  return null;
}

/// Full-screen overlay: dims the dashboard with a spotlight hole on the current
/// button, and a text box pointing to it. Uses the same dashboard UI (visible underneath).
class DashboardTourOverlay extends StatefulWidget {
  const DashboardTourOverlay({
    super.key,
    required this.bottomNavKey,
    required this.appBarActionsKey,
    required this.onComplete,
  });

  static const String _prefKey = 'dashboard_tour_completed';

  /// Returns true if the dashboard tour has not been completed yet.
  static Future<bool> shouldShowTour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) != true;
  }

  /// Clears the tour completed flag so the tour will show again (e.g. for testing).
  static Future<void> resetTour() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  final GlobalKey bottomNavKey;
  final GlobalKey appBarActionsKey;
  final VoidCallback onComplete;

  @override
  State<DashboardTourOverlay> createState() => _DashboardTourOverlayState();
}

class _DashboardTourOverlayState extends State<DashboardTourOverlay> {
  int _currentStep = 0;
  List<Rect?> _targetRects = [];
  bool _measured = false;

  static const double _spotlightPadding = 12;
  static const double _dimOpacity = 0.75;

  static final List<DashboardTourStep> _steps = [
    const DashboardTourStep(
      title: 'Your dashboard',
      description:
          'You have 5 tabs at the bottom: Upload, My Files, Favorites, Expenses, and Map. '
          'Use them to print documents, track your files, and find shops.',
    ),
    const DashboardTourStep(
      title: 'Upload',
      description:
          'Tap this tab to add your files. Set copies, paper size, and color, then choose '
          'Queue Print (select a shop) or Private Print (get a code). Tap Upload when ready.',
    ),
    const DashboardTourStep(
      title: 'Queue Print',
      description:
          'Select a shop and upload your file. Your print joins that shop\'s queue. '
          'You get a queue position and can collect when it\'s your turn.',
    ),
    const DashboardTourStep(
      title: 'Private Print',
      description:
          'Upload your file and get a unique code. Visit any shop on the Map, '
          'share the code with the shopkeeper, and collect your prints.',
    ),
    const DashboardTourStep(
      title: 'My Files',
      description:
          'See all your uploads, their status, and your codes in one place.',
    ),
    const DashboardTourStep(
      title: 'Favorites',
      description:
          'Save your preferred shops here for quick access when uploading.',
    ),
    const DashboardTourStep(
      title: 'Expenses',
      description:
          'View your print spending and wallet history here.',
    ),
    const DashboardTourStep(
      title: 'Map',
      description:
          'Find nearby shops and see if they\'re open or closed.',
    ),
    const DashboardTourStep(
      title: 'Top bar',
      description:
          'Your wallet balance is shown here. Tap it or the profile icon for '
          'Wallet, Profile, and Logout.',
    ),
  ];

  void _measureTargets() {
    final navContext = widget.bottomNavKey.currentContext;
    final appBarContext = widget.appBarActionsKey.currentContext;
    if (navContext == null || !navContext.mounted) return;
    if (appBarContext == null || !appBarContext.mounted) return;

    final list = <Rect?>[];

    final navBox = widget.bottomNavKey.currentContext?.findRenderObject() as RenderBox?;
    if (navBox != null && navBox.hasSize) {
      final navRect = navBox.localToGlobal(Offset.zero) & navBox.size;
      final itemWidth = navRect.width / 5;
      for (int i = 0; i < 5; i++) {
        list.add(Rect.fromLTWH(
          navRect.left + i * itemWidth,
          navRect.top,
          itemWidth,
          navRect.height,
        ));
      }
    } else {
      for (int i = 0; i < 5; i++) list.add(null);
    }

    final appBarBox = widget.appBarActionsKey.currentContext?.findRenderObject() as RenderBox?;
    if (appBarBox != null && appBarBox.hasSize) {
      list.add(appBarBox.localToGlobal(Offset.zero) & appBarBox.size);
    } else {
      list.add(null);
    }

    if (mounted) setState(() {
      _targetRects = list;
      _measured = true;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureTargets());
  }

  @override
  void didUpdateWidget(DashboardTourOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bottomNavKey != widget.bottomNavKey ||
        oldWidget.appBarActionsKey != widget.appBarActionsKey) {
      _measureTargets();
    }
  }

  Future<void> _completeTour() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(DashboardTourOverlay._prefKey, true);
    if (mounted) widget.onComplete();
  }

  Rect? _getHighlightRect() {
    final targetIndex = _stepToTargetIndex(_currentStep);
    if (targetIndex == null || targetIndex >= _targetRects.length) return null;
    final r = _targetRects[targetIndex];
    if (r == null) return null;
    return r.inflate(_spotlightPadding);
  }

  /// Converts global rect to overlay (body) local coordinates.
  Rect? _getHighlightRectLocal(BuildContext context) {
    final global = _getHighlightRect();
    if (global == null) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return global;
    final origin = box.localToGlobal(Offset.zero);
    return global.translate(-origin.dx, -origin.dy);
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_currentStep];
    final isLast = _currentStep == _steps.length - 1;
    final highlightRectLocal = _measured ? _getHighlightRectLocal(context) : null;
    final highlightRectGlobal = _measured ? _getHighlightRect() : null;
    final size = MediaQuery.sizeOf(context);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Dimmed layer with spotlight hole (in local coordinates)
          LayoutBuilder(
            builder: (context, constraints) {
              return CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _SpotlightPainter(
                  highlightRect: highlightRectLocal,
                  dimColor: Colors.black.withValues(alpha: _dimOpacity),
                ),
              );
            },
          ),

          // Skip button (top right)
          if (!isLast)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 16,
              child: TextButton(
                onPressed: _completeTour,
                child: const Text(
                  'Skip',
                  style: TextStyle(color: AppColors.white70, fontSize: 16),
                ),
              ),
            ),

          // Text box: position above or below the spotlight
          Positioned(
            left: 20,
            right: 20,
            top: _cardTop(size, highlightRectGlobal),
            child: _CardContent(
              step: step,
              isLast: isLast,
              onNext: () {
                if (isLast) {
                  _completeTour();
                } else {
                  setState(() => _currentStep++);
                }
              },
            ),
          ),

          // Page indicators (bottom center, above nav so they're visible)
          Positioned(
            left: 0,
            right: 0,
            bottom: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _steps.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentStep == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentStep == index
                        ? AppColors.pink500
                        : AppColors.white30,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _cardTop(Size size, Rect? highlightRect) {
    if (highlightRect == null) {
      return size.height * 0.2;
    }
    final cardHeight = 180.0;
    if (highlightRect.top > size.height * 0.5) {
      return highlightRect.top - cardHeight - 24;
    }
    return highlightRect.bottom + 16;
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? highlightRect;
  final Color dimColor;

  _SpotlightPainter({this.highlightRect, required this.dimColor});

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    if (highlightRect == null) {
      canvas.drawRect(fullRect, Paint()..color = dimColor);
      return;
    }
    final hole = RRect.fromRectAndRadius(
      highlightRect!.intersect(fullRect),
      const Radius.circular(12),
    );
    final fullPath = Path()..addRect(fullRect);
    final holePath = Path()..addRRect(hole);
    final dimmedPath = Path.combine(PathOperation.difference, fullPath, holePath);
    canvas.drawPath(dimmedPath, Paint()..color = dimColor);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.highlightRect != highlightRect || oldDelegate.dimColor != dimColor;
  }
}

class _CardContent extends StatelessWidget {
  final DashboardTourStep step;
  final bool isLast;
  final VoidCallback onNext;

  const _CardContent({
    required this.step,
    required this.isLast,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.indigo900,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.white20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            step.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            step.description,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.white70,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.pink500,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                isLast ? 'Done' : 'Next',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
