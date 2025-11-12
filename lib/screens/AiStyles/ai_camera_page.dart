import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

class AiCameraPage extends StatefulWidget {
  const AiCameraPage({super.key});

  @override
  State<AiCameraPage> createState() => _AiCameraPageState();
}

class _AiCameraPageState extends State<AiCameraPage> {
  void _showBookingDialog(Map<String, dynamic> style) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Book: ${style['name'] ?? 'Unknown'}'),
        content: Text('Proceed to book this style?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // TODO: Implement booking logic or navigation
            },
            child: const Text('Book Now'),
          ),
        ],
      ),
    );
  }

  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  List<CameraDescription>? _cameras;
  bool _processing = false;
  String? _detectedFaceShape;
  List<Map<String, dynamic>> _recommendations = [];
  bool _loadingRecommendations = false;
  String? _lastCapturedImagePath;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    final frontCamera = _cameras?.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras!.first,
    );
    _controller = CameraController(frontCamera!, ResolutionPreset.medium);
    _initializeControllerFuture = _controller!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _captureAndDetectFace() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _processing = true);
    try {
      final file = await _controller!.takePicture();
      _lastCapturedImagePath = file.path;
      final inputImage = InputImage.fromFilePath(file.path);
      final options = FaceDetectorOptions(
        enableContours: true,
        enableClassification: true,
      );
      final faceDetector = FaceDetector(options: options);
      final faces = await faceDetector.processImage(inputImage);
      await faceDetector.close();
      String result = 'No face detected.';
      String? faceShape;
      double? confidence;
      if (faces.isNotEmpty) {
        final face = faces.first;
        final rect = face.boundingBox;
        final aspect = rect.width / rect.height;
        // Use smilingProbability as a placeholder for confidence (ML Kit does not provide face shape confidence)
        confidence =
            face.smilingProbability ?? 0.85; // fallback to 85% if not available
        if (aspect > 0.95 && aspect < 1.05) {
          result = 'Round face';
          faceShape = 'round';
        } else if (aspect < 0.95 && rect.height > rect.width) {
          result = 'Oval face';
          faceShape = 'oval';
        } else if (aspect > 1.05 && rect.width > rect.height) {
          result = 'Square face';
          faceShape = 'square';
        } else {
          result = 'Unknown/Other face shape';
          faceShape = 'unknown';
          confidence = null;
        }
      }
      if (mounted) {
        setState(() {
          _detectedFaceShape = faceShape;
        });
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Face Shape Detected'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(result),
                if (confidence != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Colors.blueGrey,
                        fontSize: 15,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (_lastCapturedImagePath != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_lastCapturedImagePath!),
                      height: 80,
                      width: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Note: AI recommendations are not always 100% accurate. Please proceed at your own discretion. For best results, ensure your face is clearly visible and well-lit.',
                  style: TextStyle(color: Colors.red[700], fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  if (faceShape != null && faceShape != 'unknown') {
                    _fetchRecommendations(faceShape);
                  } else {
                    setState(() {
                      _recommendations = [];
                    });
                  }
                },
                child: const Text('OK'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() {
                    _detectedFaceShape = null;
                    _recommendations = [];
                    _lastCapturedImagePath = null;
                  });
                },
                child: const Text('Retake'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error'),
            content: Text('Failed to process image: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      setState(() => _processing = false);
    }
  }

  Future<void> _fetchRecommendations(String faceShape) async {
    setState(() {
      _loadingRecommendations = true;
      _recommendations = [];
    });
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'recommendations_$faceShape';
    // Try to load from cache first
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      final List<dynamic> cachedList = json.decode(cached);
      setState(() {
        _recommendations = List<Map<String, dynamic>>.from(cachedList);
        _loadingRecommendations = false;
      });
      // Optionally, fetch in background to update cache
      _fetchAndCacheRecommendations(faceShape, prefs, cacheKey);
      return;
    }
    // If not cached, fetch and cache
    await _fetchAndCacheRecommendations(faceShape, prefs, cacheKey);
  }

  Future<void> _fetchAndCacheRecommendations(
    String faceShape,
    SharedPreferences prefs,
    String cacheKey,
  ) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('services')
          .where('tags', arrayContains: faceShape)
          .get();
      final docs = querySnapshot.docs;
      if (docs.isNotEmpty) {
        final recs = docs.map((doc) => doc.data()).toList();
        await prefs.setString(cacheKey, json.encode(recs));
        setState(() {
          _recommendations = List<Map<String, dynamic>>.from(recs);
        });
      } else {
        await prefs.setString(cacheKey, json.encode([]));
        setState(() {
          _recommendations = [];
        });
      }
    } catch (e) {
      setState(() {
        _recommendations = [];
      });
    } finally {
      setState(() {
        _loadingRecommendations = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _controller == null
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return Stack(
                    children: [
                      // Camera preview with rounded corners
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio,
                            child: CameraPreview(_controller!),
                          ),
                        ),
                      ),
                      // Lighting note
                      Positioned(
                        top: 90,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.yellow[100]?.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Tip: Being in a well-lit area will improve AI accuracy.',
                              style: TextStyle(
                                color: Colors.brown,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      // Top overlay bar
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.black87, Colors.transparent],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          child: SafeArea(
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                                const Spacer(),
                                const Padding(
                                  padding: EdgeInsets.only(right: 16),
                                  child: Text(
                                    'AI Camera',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Bottom overlay bar
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 120,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.transparent, Colors.black87],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          child: Center(
                            child: GestureDetector(
                              onTap: _processing ? null : _captureAndDetectFace,
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: _processing
                                      ? Colors.grey
                                      : Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 4,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.camera_alt,
                                  color: Colors.black,
                                  size: 36,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Recommendations display
                      if (_detectedFaceShape != null)
                        Positioned(
                          bottom: 130,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            color: Colors.black.withOpacity(0.7),
                            child: _loadingRecommendations
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _recommendations.isNotEmpty
                                ? SizedBox(
                                    height: 180,
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _recommendations.length,
                                      itemBuilder: (context, idx) {
                                        final style = _recommendations[idx];
                                        return Container(
                                          width: 180,
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black26,
                                                blurRadius: 6,
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    const BorderRadius.only(
                                                      topLeft: Radius.circular(
                                                        16,
                                                      ),
                                                      topRight: Radius.circular(
                                                        16,
                                                      ),
                                                    ),
                                                child: style['imageUrl'] != null
                                                    ? Image.network(
                                                        style['imageUrl'],
                                                        height: 80,
                                                        width: 180,
                                                        fit: BoxFit.cover,
                                                      )
                                                    : Container(
                                                        height: 80,
                                                        width: 180,
                                                        color: Colors.grey[300],
                                                        child: const Icon(
                                                          Icons.image,
                                                          size: 40,
                                                        ),
                                                      ),
                                              ),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 4,
                                                      horizontal: 8,
                                                    ),
                                                child: Text(
                                                  style['name'] ?? 'Unknown',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                              if (style['price'] != null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 4,
                                                      ),
                                                  child: Text(
                                                    '₱${style['price']}',
                                                    style: const TextStyle(
                                                      color: Colors.green,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 4,
                                                    ),
                                                child: ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.purple,
                                                    foregroundColor:
                                                        Colors.white,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                  ),
                                                  onPressed: () =>
                                                      _showBookingDialog(style),
                                                  child: const Text('Book Now'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  )
                                : Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Text(
                                        'No recommendations found for your face shape.',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  );
                } else {
                  return const Center(child: CircularProgressIndicator());
                }
              },
            ),
    );
  }
}
