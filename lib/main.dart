import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:record/record.dart';

// models for your JSON tree from /get_structure
class FileNode {
  final String name;
  final bool isFolder;
  final String? path;           // only for files
  final List<FileNode> children; // only for folders

  FileNode({
    required this.name,
    required this.isFolder,
    this.path,
    this.children = const [],
  });

  factory FileNode.fromJson(Map<String, dynamic> j, [String? parentPath]) {
    final p = parentPath == null ? j['name'] : '$parentPath/${j['name']}';
    if (j['type'] == 'folder') {
      return FileNode(
        name: j['name'],
        isFolder: true,
        children: (j['children'] as List)
            .map((c) => FileNode.fromJson(c as Map<String, dynamic>, p))
            .toList(),
      );
    } else {
      return FileNode(name: j['name'], isFolder: false, path: p);
    }
  }
}

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
class _LoadingScreenState extends State<LoadingScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToHome();
  }

  Future<void> _navigateToHome() async {
    // Simulate loading or perform initialization tasks
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const FileManagerHomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text(
              "Loading File Manager...",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  runApp(
    ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'Voice File Manager',
          // ─── Light Theme ──────────────────────────────────────────────
          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.white,
            canvasColor: const Color(0xFFf5f5f5),            // main body bg
            drawerTheme: const DrawerThemeData(
              backgroundColor: Color(0xFF181818),            // left drawer bg
            ),
            listTileTheme: const ListTileThemeData(
              textColor: Colors.black,                     // drawer & list text
              iconColor: Colors.black,                     // drawer icons
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFE0E0E0),            // light appbar
              iconTheme: IconThemeData(color: Colors.black87),
            ),
            cardColor: Colors.white,
          ),

          // ─── Dark Theme ───────────────────────────────────────────────
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.deepPurple,
            scaffoldBackgroundColor: const Color(0xFF303030), // main body bg
            canvasColor: const Color(0xFF303030),
            drawerTheme: const DrawerThemeData(
              backgroundColor: Color(0xFF181818),            // left drawer bg
            ),
            listTileTheme: const ListTileThemeData(
              textColor: Colors.white70,
              iconColor: Colors.white70,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF181818),
              iconTheme: IconThemeData(color: Colors.white70),
            ),
            cardColor: const Color(0xFF1E1E1E),
          ),

          themeMode: currentMode,  // your ValueNotifier<ThemeMode>
          home: const FileManagerHomePage(),
          debugShowCheckedModeBanner: false,
        );

      },
    ),
  );
}



class MyAppWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'File Manager',
          theme: ThemeData.light().copyWith(
            scaffoldBackgroundColor: Colors.grey[100],
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.blueGrey,
              foregroundColor: Colors.white,
            ),
            cardColor: Colors.white,
            inputDecorationTheme: InputDecorationTheme(
              fillColor: Theme.of(context).canvasColor,
              filled: true,
              border: OutlineInputBorder(),
            ),

          ),
          darkTheme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: Colors.black,
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
            ),
            cardColor: Colors.grey[900],
            inputDecorationTheme: InputDecorationTheme(
              fillColor: Colors.grey[850],
              filled: true,
              border: OutlineInputBorder(),
            ),
          ),
          themeMode: themeMode,
          home: FileManagerApp(), // This should point to your home widget
        );
      },
    );
  }
}


class FileManagerApp extends StatelessWidget {
  const FileManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice File Manager',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const LoadingScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class FileManagerHomePage extends StatefulWidget {
  const FileManagerHomePage({super.key});

  @override
  _FileManagerHomePageState createState() => _FileManagerHomePageState();
}
String _lastTranscript = '';
class _FileManagerHomePageState extends State<FileManagerHomePage> {


  // This will hold files from all folders for search purposes.
  List<Map<String, dynamic>> allFiles = [];
  bool isLoading = true;
  FileNode? rootNode;
  String currentFolder = 'Home';
  int? hoveredKey;     // ← add this
  // Variables for selection, renaming, and search.
  Set<String> selectedFiles = {};
  bool isSelecting = false;
  bool isRenaming = false;
  TextEditingController searchController = TextEditingController();
  String searchQuery = "";

  // Currently selected folder key (default to Home).

  // Speech recognition variables.
  late stt.SpeechToText _speech;
  bool _isListening = false;

  @override
  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();

    // keep your search listener
    searchController.addListener(() {
      setState(() {
        searchQuery = searchController.text.toLowerCase();
      });
    });

    // ─── boot up the tree view instead of a flat fetch ───
    _changeFolder('Home');

    // still populate your flat list for search
    fetchAllFiles();
  }


  // Fetch files for the current folder.
  Future<void> fetchStructure(String folderKey) async {
    final url = Uri.parse(
        'http://localhost:8000/get_structure?path=${Uri.encodeComponent(folderKey)}'
    );
    final resp = await http.get(url);
    if (resp.statusCode == 200) {
      final jsonBody = json.decode(resp.body) as Map<String, dynamic>;
      setState(() {
        rootNode = FileNode.fromJson(jsonBody, folderKey);
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
      // you may want to show an error Snackbar here
    }
  }
  /// Recursively builds ExpansionTiles (folders) and ListTiles (files)
  List<Widget> _buildNodes(List<FileNode> nodes) {
    return nodes.map((node) {
      if (node.isFolder) {
        return ExpansionTile(
          leading: const Icon(Icons.folder),
          title: Text(node.name),
          children: _buildNodes(node.children),
        );
      } else {
        return MouseRegion(
          onEnter: (_) => setState(() => hoveredKey = node.path.hashCode),
          onExit:  (_) => setState(() => hoveredKey = null),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: hoveredKey == node.path.hashCode
                  ? Colors.grey.withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              leading: isSelecting
                  ? Checkbox(
                value: selectedFiles.contains(node.path),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    selectedFiles.add(node.path!);
                  } else {
                    selectedFiles.remove(node.path!);
                  }
                }),
              )
                  : Icon(
                Icons.insert_drive_file,
                color: Theme.of(context).brightness == Brightness.light
                    ? Colors.black54
                    : Colors.white70,
              ),
              title: GestureDetector(
                onTap: () {
                  if (isRenaming) {
                    _showRenameDialog(node.path!, node.name);
                  } else {
                    _openFileInBrowser(node.path!);
                  }
                },
                child: Text(node.name),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () => _showFileInfoDialog({
                  'name': node.name,
                  'path': node.path,
                  'is_dir': false,
                }),
              ),
            ),
          ),
        );
      }
    }).toList();
  }

  // Fetch files from all folders and aggregate into allFiles.
  Future<void> fetchAllFiles() async {
    List<Map<String, dynamic>> aggregated = [];
    // List of folder keys as used in your server mapping.
    for (String folder in ["Home", "Documents", "Downloads"]) {
      final url = Uri.parse(
          'http://localhost:8000/files?path=${Uri.encodeComponent(folder)}');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        List<Map<String, dynamic>> folderFiles =
        List<Map<String, dynamic>>.from(json.decode(response.body));
        aggregated.addAll(folderFiles);
      }
    }
    setState(() {
      allFiles = aggregated;
    });
  }
  void _changeFolder(String folder) {
    setState(() {
      currentFolder = folder;
      isLoading = true;
    });
    fetchStructure(folder);
    fetchAllFiles(); // keep your search index up to date
  }
  // Change folder and fetch its files.

  // Open file in the browser using url_launcher.
  Future<void> _openFileInBrowser(String path) async {
    final url = 'http://localhost:8000/file-content?path=$path';
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      debugPrint("Could not launch $url");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open file.")),
      );
    }
  }

  // Delete a file on the server.
  Future<void> deleteFileOnServer(String path) async {
    final url = Uri.parse('http://localhost:8000/delete-file');
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: json.encode({'path': path}),
    );
    if (response.statusCode == 200) {
      debugPrint("File deleted successfully on server.");
    } else {
      debugPrint("Error deleting file: ${response.body}");
      throw Exception("Failed to delete file");
    }
  }

  // Rename a file on the server.
  Future<void> renameFileOnServer(String oldPath, String newName) async {
    final url = Uri.parse('http://localhost:8000/rename-file');
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: json.encode({'path': oldPath, 'newName': newName}),
    );
    if (response.statusCode == 200) {
      debugPrint("File renamed successfully on server.");
    } else {
      debugPrint("Error renaming file: ${response.body}");
      throw Exception("Failed to rename file");
    }
  }

  Future<void> addFileOnServer(String folder, String name, String content,
      String type) async {
    final url = Uri.parse('http://localhost:8000/add-file');
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: json.encode({
        'folder': folder,
        'name': name,
        'content': content,
        'type': type,
      }),
    );
    if (response.statusCode == 200) {
      debugPrint("File added successfully on server.");
    } else {
      debugPrint("Error adding file: ${response.body}");
      throw Exception("Failed to add file");
    }
  }

  // Function to pick any file (for binary files) and return its Base64 content.
  Future<String> pickAnyFile() async {
    final input = html.FileUploadInputElement();
    input.accept = "*/*"; // Accept any file type.
    input.click();
    await input.onChange.first;
    final file = input.files!.first;
    final reader = html.FileReader();
    reader.readAsDataUrl(file);
    await reader.onLoad.first;
    // The result is a Data URL: "data:application/octet-stream;base64,...."
    final result = reader.result as String;
    return result
        .split(',')
        .last; // Return only the Base64 part.
  }

  /// Calls Python to record & transcribe, then returns the text.
  /// 1. Calls Flask `/transcribe` to record & transcribe via demmo.py
  Future<String?> _fetchTranscription() async {
    final uri = Uri.parse('http://localhost:8000/transcribe');
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body)['transcription'] as String;
    } else {
      debugPrint('Transcription error: ${resp.body}');
      return null;
    }
  }

  /// 2. Calls Flask `/execute-transcription` to run execute.py
  Future<String?> _executeTranscription() async {
    final uri = Uri.parse('http://localhost:8000/execute-transcription');
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body)['command'] as String;
    } else {
      debugPrint('Execution error: ${resp.body}');
      return null;
    }
  }


  // Helper: Get friendly file type from file name.
  String getFileType(String fileName) {
    String extension = "";
    if (fileName.contains(".")) {
      extension = fileName
          .split(".")
          .last
          .toLowerCase();
    }
    switch (extension) {
      case "jpg":
      case "jpeg":
      case "png":
      case "gif":
        return "Image ($extension)";
      case "pdf":
        return "PDF Document";
      case "txt":
        return "Text File";
      case "doc":
      case "docx":
        return "Word Document";
      case "xls":
      case "xlsx":
        return "Excel Spreadsheet";
      case "ppt":
      case "pptx":
        return "PowerPoint Presentation";
      case "mp3":
        return "Audio File";
      case "mp4":
      case "avi":
        return "Video File";
      default:
        return "File (${extension.isNotEmpty ? extension : 'unknown'})";
    }
  }

  // Show dialog to add a new file.
  // Provides radio buttons to select "Text" or "Binary" type.
  void _showAddFileDialog() {
    TextEditingController nameController = TextEditingController();
    TextEditingController contentController = TextEditingController();
    // Default file type is text.
    String fileType = "text";
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text("Add New File"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                        labelText: "File Name (include extension)"),
                  ),
                  // Radio buttons to select file type.
                  Row(
                    children: [
                      Radio<String>(
                        value: "text",
                        groupValue: fileType,
                        onChanged: (value) {
                          setStateDialog(() {
                            fileType = value!;
                          });
                        },
                      ),
                      const Text("Text"),
                      Radio<String>(
                        value: "binary",
                        groupValue: fileType,
                        onChanged: (value) {
                          setStateDialog(() {
                            fileType = value!;
                          });
                        },
                      ),
                      const Text("Binary"),
                    ],
                  ),
                  if (fileType == "text")
                    TextField(
                      controller: contentController,
                      decoration: const InputDecoration(
                          labelText: "File Content"),
                      maxLines: 5,
                    )
                  else
                    ElevatedButton(
                      onPressed: () async {
                        // Pick any file and read as Base64.
                        final base64Content = await pickAnyFile();
                        setStateDialog(() {
                          contentController.text = base64Content;
                        });
                      },
                      child: const Text("Choose File"),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                child: const Text("Cancel"),
                onPressed: () => Navigator.pop(context),
              ),
              TextButton(
                child: const Text("Add"),
                onPressed: () async {
                  if (nameController.text.isNotEmpty) {
                    try {
                      await addFileOnServer(
                          currentFolder,
                          nameController.text,
                          contentController.text,
                          fileType);
                      await fetchStructure(currentFolder);

                      await fetchAllFiles();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              "File ${nameController.text} added successfully"),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    } catch (e) {
                      debugPrint("Error adding file: $e");
                    }
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          );
        });
      },
    );
  }

  // Show rename dialog that calls the server endpoint.
  void _showRenameDialog(String filePath, String currentName) {
    final renameController = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Rename File"),
          content: TextField(
            controller: renameController,
            decoration: const InputDecoration(labelText: "New File Name"),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text("Rename"),
              onPressed: () async {
                final newName = renameController.text;
                try {
                  await renameFileOnServer(filePath, newName);
                  await fetchStructure(currentFolder);
                  await fetchAllFiles();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("File renamed to $newName"),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } catch (e) {
                  debugPrint("Rename error: $e");
                }
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  // Confirm delete dialog that calls the server endpoint.
  void _confirmDeleteFiles() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Confirm Delete"),
          content: Text("Are you sure you want to delete ${selectedFiles
              .length} file(s)?"),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text("Delete"),
              onPressed: () async {
                try {
                  // delete each selected file by its path
                  for (var filePath in selectedFiles) {
                    await deleteFileOnServer(filePath);
                  }

                  // refresh your tree and search index
                  await fetchStructure(currentFolder);
                  await fetchAllFiles();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("${selectedFiles.length} file(s) deleted"),
                      duration: const Duration(seconds: 2),
                    ),
                  );

                  setState(() {
                    selectedFiles.clear();
                    isSelecting = false;
                  });
                } catch (e) {
                  // TODO: handle errors (e.g. show an error snackbar)
                }
                catch (e) {
                  debugPrint("Deletion error: $e");
                }
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  // Show file info dialog (for metadata), including file type.
  void _showFileInfoDialog(Map<String, dynamic> file) {
    String fileTypeInfo = file['is_dir']
        ? "Folder"
        : getFileType(file['name']);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(file['name']),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Path: ${file['path']}"),
              Text("Type: $fileTypeInfo"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  // Filter files based on the search query.
  // If there's a search query, search across all files; otherwise, show current folder.


  // Voice recognition: Toggle listening using speech_to_text.
  Future<void> _toggleListening() async {
    if (!_isListening) {
      // initialize
      bool available = await _speech.initialize(
        onStatus: (status) => print("Speech status: $status"),
        onError: (error) => print("Speech error: ${error.errorMsg}"),
      );
      if (!available) {
        print("Speech recognition unavailable");
        return;
      }
      setState(() {
        _isListening = true;
      });

      _speech.listen(
        onResult: (res) async {
          // Only act when final result arrives
          if (res.finalResult) {
            String transcript = res.recognizedWords;
            print("Final transcript: $transcript");

            setState(() {
              _isListening = false;
              _lastTranscript = transcript;
            });

            // Call your Flask endpoint to execute
            /////here i wnat to do
          }
        },
        listenFor: const Duration(seconds: 7),
        pauseFor: const Duration(seconds: 2),
        partialResults: false,
        onSoundLevelChange: null,
        cancelOnError: true,
        localeId: 'en_US',
      );
    } else {
      // manually stop if already listening
      await _speech.stop();
      setState(() {
        _isListening = false;
      });
      print("Stopped listening manually.");
    }
  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _speech = stt.SpeechToText();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text("Voice File Manager"),
            const Spacer(),
            Container(
              width: 250,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.light
                    ? Colors.white
                    : Colors.grey[800],
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.light
                      ? Colors.grey[400]!
                      : Colors.white24,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: TextField(
                controller: searchController,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: "Search files...",
                  border: InputBorder.none,
                  icon: Icon(
                    Icons.search,
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.black54
                        : Colors.white70,
                  ),
                  contentPadding: const EdgeInsets.only(top: 15), // slight downward shift
                  isDense: true,
                ),
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.light
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),

            const Spacer(),
          ],
        ),
        actions: [
          IconButton(
            icon: ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (_, mode, __) => Icon(
                  mode == ThemeMode.light
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded
              ),
            ),
            tooltip: 'Toggle Dark Mode',
            onPressed: () {
              themeNotifier.value = themeNotifier.value == ThemeMode.light
                  ? ThemeMode.dark
                  : ThemeMode.light;
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add File',
            onPressed: _showAddFileDialog,
          ),
          IconButton(
            icon: Icon(Icons.brightness_6),
            onPressed: () {
              themeNotifier.value =
              themeNotifier.value == ThemeMode.light
                  ? ThemeMode.dark
                  : ThemeMode.light;
            },
          ),
          IconButton(
            icon: Icon(isSelecting ? Icons.check : Icons.delete),
            tooltip: isSelecting ? 'Confirm Deletion' : 'Delete Files',
            onPressed: () {
              if (isSelecting) {
                _confirmDeleteFiles();
              } else {
                setState(() {
                  isSelecting = true;
                });
              }
            },
          ),
          IconButton(
            icon: Icon(isRenaming
                ? Icons.check
                : Icons.drive_file_rename_outline),
            tooltip: isRenaming ? 'Confirm Rename' : 'Rename File',
            onPressed: () {
              setState(() {
                isRenaming = !isRenaming;
              });
            },
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: Theme.of(context).drawerTheme.backgroundColor,
        child: ListView(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Colors.blue),
              child: const Text(
                'Folders',
                style: TextStyle(fontSize: 24, color: Colors.white),
              ),
            ),
            for (final entry in ['Home', 'Documents', 'Downloads'])
              ListTile(
                leading: Icon(
                  entry == 'Home' ? Icons.home : Icons.folder,
                  color: Theme.of(context).brightness == Brightness.light
                      ? Colors.white54
                      : Colors.white70,
                ),
                title: Text(
                  entry,
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.white
                        : Colors.white,
                  ),
                ),
                onTap: () {
                  _changeFolder(entry);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),

      body: Row(
        children: [
          // ── LEFT SIDEBAR ───────────────────────────────────────
          Expanded(
            flex: 1,
            child: Container(
              // match the scaffold background
              color: Theme.of(context).scaffoldBackgroundColor,
              child: ListView(
                children: [
                  for (final entry in ['Home', 'Documents', 'Downloads'])
                    ListTile(
                      leading: Icon(
                        entry == 'Home' ? Icons.home : Icons.folder,
                        // icon color adapts to brightness
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.black54
                            : Colors.white70,
                      ),
                      title: Text(
                        entry,
                        style: TextStyle(
                          // text color adapts to brightness
                          color: Theme.of(context).brightness == Brightness.light
                              ? Colors.black
                              : Colors.white,
                        ),
                      ),
                      onTap: () => _changeFolder(entry),
                      selected: currentFolder == entry,
                      selectedTileColor: Theme.of(context).brightness == Brightness.light
                          ? Colors.blue[50]
                          : Colors.white10,
                    ),
                ],
              ),
            ),
          ),

          const VerticalDivider(width: 1),

          // ── MAIN CONTENT ───────────────────────────────────────
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              child: isLoading || rootNode == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: _buildNodes(rootNode!.children),
              ),


            ),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // 1) Record & transcribe
          final text = await _fetchTranscription();
          if (text == null) return;

          // 2) Convert & execute
          final cmd = await _executeTranscription();
          if (cmd == null) return;

          // 3) Refresh your file list to reflect filesystem changes
          await fetchStructure(currentFolder);

          await fetchAllFiles();

          // 4) (Optional) show feedback
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ran command: $cmd')),
          );
        },
        child: const Icon(Icons.mic),
        tooltip: 'Record & Execute',
      ),
    );
  }
}