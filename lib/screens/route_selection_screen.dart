import 'package:flutter/material.dart';
import 'home_screen.dart';
import '../local_storage.dart';

class RouteSelectionScreen extends StatelessWidget {
  final Map<String, dynamic>? conductor;

  const RouteSelectionScreen({super.key, this.conductor});

  void _selectRoute(BuildContext context, String routeDirection) {
    // Save this navigation for app resume from recent apps
    LocalStorage.saveLastScreen('home_screen', {'routeDirection': routeDirection == 'North' ? 'north_to_south' : 'south_to_north'});
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomeScreen(routeDirection: routeDirection == 'North' ? 'north_to_south' : 'south_to_north', conductor: conductor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Fixed sizes optimized for 5.5" screen
    const double horizontalPadding = 16.0;
    const double verticalSpacing = 16.0;
    const double headerFontSize = 22.0;
    const double routeLabelFontSize = 16.0;
    const double routeSubLabelFontSize = 12.0;
    const double routeSpacing = 8.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: 12.0,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.green[700],
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      )
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      "SELECT ROUTE",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: headerFontSize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: verticalSpacing),

                // Route 1: North (Nasugbu → Batangas Grand)
                GestureDetector(
                onTap: () => _selectRoute(
                  context,
                  'North',
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    border: Border.all(color: Colors.green[700]!, width: 2),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'NORTH',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: routeSubLabelFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Nasugbu',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: routeLabelFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.arrow_forward, color: Colors.green[700], size: 16),
                          const SizedBox(width: 6),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Batangas Grand',
                        style: TextStyle(
                          fontSize: routeLabelFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

                const SizedBox(height: routeSpacing),

                // Route 2: South (Batangas Grand → Nasugbu)
                GestureDetector(
                onTap: () => _selectRoute(
                  context,
                  'South',
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    border: Border.all(color: Colors.green[700]!, width: 2),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'SOUTH',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: routeSubLabelFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Batangas Grand',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: routeLabelFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.arrow_forward, color: Colors.green[700], size: 16),
                          const SizedBox(width: 6),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Nasugbu',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: routeLabelFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

                const SizedBox(height: verticalSpacing),

                // Info text
                Text(
                  'Tap a route to continue',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                      ),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}