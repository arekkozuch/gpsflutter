// screens/views/sessions_view.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../file_viewer_screen.dart';
import '../../services/file_download_service.dart';

class SessionsView extends StatefulWidget {
  final List<Map<String, dynamic>> sessionFiles;
  final bool isLoadingSessions;
  final String lastCommandResponse;
  final bool isLogging;
  final Function(String) onSendCommand;
  final VoidCallback onRefreshFiles;
  final Function(String) onDownloadFile;
  final Function(String) onDeleteFile;

  const SessionsView({
    super.key,
    required this.sessionFiles,
    required this.isLoadingSessions,
    required this.lastCommandResponse,
    required this.isLogging,
    required this.onSendCommand,
    required this.onRefreshFiles,
    required this.onDownloadFile,
    required this.onDeleteFile,
  });

  @override
  State<SessionsView> createState() => _SessionsViewState();
}

class _SessionsViewState extends State<SessionsView> {
  List<DownloadedFile> _downloadedFiles = [];
  bool _isLoadingDownloads = false;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _loadDownloadedFiles();
    
    // Start timer to refresh download progress
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() {
          // This will trigger UI rebuild to show updated progress
        });
      }
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDownloadedFiles() async {
    setState(() {
      _isLoadingDownloads = true;
    });
    
    final files = await FileDownloadService().getDownloadedFiles();
    
    setState(() {
      _downloadedFiles = files;
      _isLoadingDownloads = false;
    });
  }

  void _viewFile(DownloadedFile file) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FileViewerScreen(
          filename: file.filename,
          filePath: file.filePath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Device Control Panel
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.settings, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text("Device Control", style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => widget.onSendCommand("STATUS"),
                        icon: const Icon(Icons.info),
                        label: const Text("Status"),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => widget.onSendCommand("SD_INFO"),
                        icon: const Icon(Icons.sd_card),
                        label: const Text("SD Info"),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => widget.onSendCommand("IMU_INFO"),
                        icon: const Icon(Icons.compass_calibration),
                        label: const Text("IMU Info"),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => widget.onSendCommand("BAT_INFO"),
                        icon: const Icon(Icons.battery_std),
                        label: const Text("Battery"),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => widget.onSendCommand("RESET_STATS"),
                        icon: const Icon(Icons.refresh),
                        label: const Text("Reset"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // File Management
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text("File Management", style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: widget.isLoadingSessions ? null : widget.onRefreshFiles,
                          icon: widget.isLoadingSessions 
                              ? const SizedBox(
                                  width: 16, 
                                  height: 16, 
                                  child: CircularProgressIndicator(strokeWidth: 2)
                                )
                              : const Icon(Icons.refresh),
                          label: const Text("Refresh Files"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (widget.isLogging) {
                              await widget.onSendCommand("STOP_LOG");
                            } else {
                              await widget.onSendCommand("START_LOG");
                            }
                          },
                          icon: Icon(widget.isLogging ? Icons.stop : Icons.play_arrow),
                          label: Text(widget.isLogging ? "Stop Log" : "Start Log"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.isLogging ? Colors.red : Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Session Files List (Remote Files)
          if (widget.sessionFiles.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.cloud, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text("Remote Files", style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    ...widget.sessionFiles.map((file) => _buildRemoteFileCard(file)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Downloaded Files List
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.download_done, color: Colors.green),
                      const SizedBox(width: 8),
                      Text("Downloaded Files", style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      IconButton(
                        onPressed: _loadDownloadedFiles,
                        icon: _isLoadingDownloads 
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  if (_downloadedFiles.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.folder_open, size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text("No downloaded files"),
                            Text("Download files from remote to view them here"),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._downloadedFiles.map((file) => _buildDownloadedFileCard(file)),
                ],
              ),
            ),
          ),
          
          // Command Response
          if (widget.lastCommandResponse.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.terminal, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text("Last Command", style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        widget.lastCommandResponse,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRemoteFileCard(Map<String, dynamic> file) {
    final filename = file["name"]!;
    final downloadProgress = FileDownloadService().getDownloadProgress(filename);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insert_drive_file, size: 20, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  filename,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                file["size"]!,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                file["duration"]!,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(width: 16),
              Icon(Icons.data_usage, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                "${file["packets"]} packets",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            file["date"]!,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
          
          // Download Progress Bar
          if (downloadProgress != null) ...[
            const SizedBox(height: 12),
            _buildDownloadProgress(downloadProgress),
          ] else ...[
            const SizedBox(height: 8),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      widget.onDownloadFile(filename);
                      // Start tracking download progress
                      // This would be handled by your BLE transfer implementation
                    },
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text("Download"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => widget.onDeleteFile(filename),
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text("Delete"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDownloadProgress(FileDownloadProgress progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: progress.progress,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress.status == DownloadStatus.completed 
                      ? Colors.green 
                      : progress.status == DownloadStatus.failed
                          ? Colors.red
                          : Colors.blue,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              "${(progress.progress * 100).toStringAsFixed(1)}%",
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              _getStatusText(progress.status),
              style: TextStyle(
                fontSize: 12,
                color: _getStatusColor(progress.status),
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            if (progress.status == DownloadStatus.downloading)
              Text(
                progress.speedFormatted,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
          ],
        ),
        if (progress.status == DownloadStatus.completed && progress.filePath != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final downloadedFile = DownloadedFile(
                  filename: progress.filename,
                  filePath: progress.filePath!,
                  size: progress.totalBytes,
                  downloadDate: progress.startTime,
                );
                _viewFile(downloadedFile);
              },
              icon: const Icon(Icons.visibility, size: 16),
              label: const Text("View File"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDownloadedFileCard(DownloadedFile file) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.file_present, size: 20, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  file.filename,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                file.sizeFormatted,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Downloaded: ${_formatDate(file.downloadDate)}",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _viewFile(file),
              icon: const Icon(Icons.visibility, size: 16),
              label: const Text("View Track"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.downloading:
        return "Downloading...";
      case DownloadStatus.completed:
        return "Download Complete";
      case DownloadStatus.failed:
        return "Download Failed";
      case DownloadStatus.cancelled:
        return "Download Cancelled";
    }
  }

  Color _getStatusColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.downloading:
        return Colors.blue;
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.failed:
        return Colors.red;
      case DownloadStatus.cancelled:
        return Colors.orange;
    }
  }

  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
  }
}