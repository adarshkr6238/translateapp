import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'overlay_main.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BubbleOverlay(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bubble Translator',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isOverlayPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    bool isGranted = await FlutterOverlayWindow.isPermissionGranted();
    if (!isGranted) {
      isGranted = await FlutterOverlayWindow.requestPermission() ?? false;
    }
    
    // Also request storage permission for saving temporary screenshots
    await Permission.storage.request();
    
    setState(() {
      _isOverlayPermissionGranted = isGranted;
    });
  }

  Future<void> _showOverlay() async {
    if (_isOverlayPermissionGranted) {
      if (await FlutterOverlayWindow.isActive()) {
        return;
      }
      await FlutterOverlayWindow.showOverlay(
        alignment: OverlayAlignment.centerRight,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: PositionGravity.auto,
        height: 600, // Adjusted height for result view
        width: 600,
      );
    } else {
      _checkPermissions();
    }
  }

  Future<void> _closeOverlay() async {
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bubble Translator')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Overlay Permission: ${_isOverlayPermissionGranted ? "Granted" : "Denied"}'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _showOverlay,
              child: const Text('Start Translator Bubble'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _closeOverlay,
              child: const Text('Stop Translator Bubble'),
            ),
          ],
        ),
      ),
    );
  }
}
