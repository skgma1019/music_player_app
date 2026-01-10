import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
// ⬇️ [필수] 내 폰의 음악을 다 털어오는 패키지
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SongListScreen(), // ⬅️ 시작 화면이 '노래 리스트'로 변경됨!
    ),
  );
}

// ==========================================
// 🎵 1. 노래 목록 화면 (삼성 뮤직 스타일)
// ==========================================
class SongListScreen extends StatefulWidget {
  const SongListScreen({super.key});

  @override
  State<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends State<SongListScreen> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  // 권한 체크 및 요청
  Future<void> _checkPermission() async {
    // 안드로이드 13 이상(SDK 33)부터는 권한 이름이 다름
    if (await Permission.audio.request().isGranted ||
        await Permission.storage.request().isGranted) {
      setState(() {
        _hasPermission = true;
      });
    } else {
      // 권한 거부 시 다시 요청하거나 안내 멘트 (간단히 처리)
      setState(() {
        _hasPermission = false;
      });
    }
  }

  Future<List<SongModel>> _getMusicFiles() async {
    // 1. 일단 다 가져옵니다.
    List<SongModel> allSongs = await _audioQuery.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    // 2. 여기서 '통화 녹음' 처럼 보이는 애들을 걸러냅니다.
    return allSongs.where((song) {
      // 파일 경로와 제목을 소문자로 바꿉니다 (검색하기 쉽게)
      String path = song.data.toLowerCase();
      String title = song.displayName.toLowerCase();

      // 🚫 제외할 키워드 리스트
      bool isCallRecording =
          path.contains('/call/') || // 삼성 갤럭시 통화녹음 폴더
          path.contains('/call recordings/') ||
          path.contains('/voice recorder/') || // 음성 녹음 폴더
          path.contains('통화 녹음') || // 한국어 파일명
          title.startsWith('call_') || // 통화녹음 파일명 패턴
          title.startsWith('010-') || // 전화번호로 시작하는 파일
          title.startsWith('02-');

      // 통화 녹음이 '아닌' 것만 리턴 (true면 살리고, false면 버림)
      return !isCallRecording;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Samsung Music (Clone)"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: !_hasPermission
          ? Center(
              child: ElevatedButton(
                onPressed: _checkPermission,
                child: const Text("음악 파일 접근 권한 허용하기"),
              ),
            )
          : FutureBuilder<List<SongModel>>(
              // ⬇️ [핵심] 기기의 모든 오디오 파일 가져오기
              future: _getMusicFiles(),
              builder: (context, item) {
                if (item.hasError) return Text("에러: ${item.error}");
                if (item.data == null) return const CircularProgressIndicator();
                if (item.data!.isEmpty) return const Text("노래가 없습니다 😢");

                // 노래 리스트 렌더링
                return ListView.builder(
                  itemCount: item.data!.length,
                  itemBuilder: (context, index) {
                    var song = item.data![index];

                    return ListTile(
                      // 앨범 커버 (없으면 음표 아이콘)
                      leading: QueryArtworkWidget(
                        id: song.id,
                        type: ArtworkType.AUDIO,
                        nullArtworkWidget: const Icon(
                          Icons.music_note,
                          size: 30,
                        ),
                      ),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        "${song.artist ?? "Unknown"} | ${song.album ?? "Unknown"}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // ⬇️ [클릭] 노래를 누르면 플레이어 화면으로 이동!
                      onTap: () {
                        if (song.data.isEmpty) return;

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MusicPlayerScreen(
                              songPath: song.data, // 파일 경로 전달
                              songTitle: song.title, // 제목 전달
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

// ==========================================
// 🎤 2. 플레이어 화면 (AI 가사 + 기능 집약)
// ==========================================
class MusicPlayerScreen extends StatefulWidget {
  // ⬇️ 리스트에서 선택한 노래 정보를 받아옴
  final String songPath;
  final String songTitle;

  const MusicPlayerScreen({
    super.key,
    required this.songPath,
    required this.songTitle,
  });

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();

  String _selectedLanguage = "auto";
  String _statusMessage = "준비 완료";
  bool _isPlaying = false;

  bool _isAnalyzing = false;
  double _progressValue = 0.0;
  Timer? _progressTimer;

  String? _manualLyrics;
  List<Map<String, dynamic>> _lyrics = [];

  int _currentIndex = -1;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  final Map<String, String> _languages = {
    "자동 감지": "auto",
    "한국어 (Korean)": "ko",
    "영어 (English)": "en",
    "일본어 (Japanese)": "ja",
  };

  @override
  void initState() {
    super.initState();
    _setupAudioListener();
    _playInitialMusic(); // ⬇️ 화면 들어오자마자 재생 시작
  }

  // 넘겨받은 파일 바로 재생
  Future<void> _playInitialMusic() async {
    try {
      await _audioPlayer.setFilePath(widget.songPath);
      _audioPlayer.play();
      setState(() {
        _isPlaying = true;
        _totalDuration = _audioPlayer.duration ?? Duration.zero;
      });
    } catch (e) {
      print("재생 에러: $e");
      setState(() {
        _statusMessage = "재생 실패: 파일 권한 확인 필요";
      });
    }
  }

  void _setupAudioListener() {
    _audioPlayer.positionStream.listen((Duration p) {
      setState(() {
        _currentPosition = p;
      });

      if (_lyrics.isEmpty) return;
      double currentSeconds = p.inMilliseconds / 1000.0;
      int foundIndex = -1;

      for (int i = 0; i < _lyrics.length; i++) {
        var line = _lyrics[i];
        double start = (line['start'] as num).toDouble();
        if (start <= currentSeconds) {
          foundIndex = i;
        } else {
          break;
        }
      }

      if (foundIndex != -1 && foundIndex != _currentIndex) {
        setState(() {
          _currentIndex = foundIndex;
        });
        _scrollToCenter(foundIndex);
      }
    });

    _audioPlayer.durationStream.listen((Duration? d) {
      setState(() {
        _totalDuration = d ?? Duration.zero;
      });
    });
  }

  void _scrollToCenter(int index) {
    if (_itemScrollController.isAttached) {
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  void _seekTo(double value) {
    final position = Duration(seconds: value.toInt());
    _audioPlayer.seek(position);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _progressTimer?.cancel();
    super.dispose();
  }

  void _startSimulatedProgress() {
    _progressTimer?.cancel();
    setState(() => _progressValue = 0.0);

    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        if (_progressValue < 0.5)
          _progressValue += 0.02;
        else if (_progressValue < 0.8)
          _progressValue += 0.005;
        else if (_progressValue < 0.95)
          _progressValue += 0.001;
      });
    });
  }

  void _completeProgress() {
    _progressTimer?.cancel();
    setState(() => _progressValue = 1.0);
    Future.delayed(const Duration(milliseconds: 500), () {
      setState(() => _isAnalyzing = false);
    });
  }

  void _togglePlay() {
    _isPlaying ? _audioPlayer.pause() : _audioPlayer.play();
    setState(() => _isPlaying = !_isPlaying);
  }

  // AI 가사 요청 (수정된 주소 반영)
  Future<void> _getAiLyrics() async {
    setState(() {
      _isAnalyzing = true;
      _currentIndex = -1;
    });
    _startSimulatedProgress();

    try {
      // ⚠️ 중요: 내 PC IP 주소로 수정 필수! (127.0.0.1은 에뮬레이터에서 안됨)
      String baseUrl = kIsWeb
          ? "http://127.0.0.1:3000"
          : "http://10.140.193.43:3000";
      var uri = Uri.parse("$baseUrl/analyze");
      var request = http.MultipartRequest('POST', uri);

      print(
        "📤 [앱 -> 서버] 선택된 언어: $_selectedLanguage / 파일: ${widget.songTitle}",
      );
      request.fields['language'] = _selectedLanguage;
      if (_manualLyrics != null && _manualLyrics!.isNotEmpty) {
        request.fields['lyrics_text'] = _manualLyrics!;
      }

      request.files.add(
        await http.MultipartFile.fromPath('audio', widget.songPath),
      );

      var response = await request.send();
      if (response.statusCode == 200) {
        var json = jsonDecode(await response.stream.bytesToString());
        setState(() {
          _lyrics = List<Map<String, dynamic>>.from(json['segments']);
        });
        _completeProgress();
      } else {
        setState(() => _statusMessage = "분석 실패 (코드: ${response.statusCode})");
        _isAnalyzing = false;
        _progressTimer?.cancel();
      }
    } catch (e) {
      setState(() => _statusMessage = "에러: $e");
      _isAnalyzing = false;
      _progressTimer?.cancel();
    }
  }

  void _showLyricsDialog() {
    TextEditingController c = TextEditingController(text: _manualLyrics);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("가사 직접 입력"),
        content: TextField(controller: c, maxLines: 10),
        actions: [
          ElevatedButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              setState(() => _manualLyrics = c.text);
              Navigator.pop(context);
            },
            child: const Text("저장"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 상단바에 노래 제목 표시
      appBar: AppBar(
        title: Text(widget.songTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context), // 뒤로가기
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // 앨범 커버 대신 아이콘
            const Icon(Icons.music_note, size: 80, color: Colors.deepPurple),
            const SizedBox(height: 10),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),

            // 언어 선택
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedLanguage,
                  items: _languages.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.value,
                          child: Text(entry.key),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedLanguage = v!),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 재생 바 (Slider)
            Column(
              children: [
                Slider(
                  min: 0,
                  max: (_totalDuration.inSeconds > 0)
                      ? _totalDuration.inSeconds.toDouble()
                      : 1.0,
                  value:
                      (_currentPosition.inSeconds.toDouble() <=
                          _totalDuration.inSeconds.toDouble())
                      ? _currentPosition.inSeconds.toDouble()
                      : 0.0,
                  activeColor: Colors.deepPurple,
                  inactiveColor: Colors.deepPurple.withOpacity(0.3),
                  onChanged: _seekTo,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(_currentPosition)),
                      Text(_formatDuration(_totalDuration)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // 버튼 or 로딩바
            _isAnalyzing
                ? Column(
                    children: [
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: _progressValue,
                              strokeWidth: 6,
                              color: Colors.deepPurple,
                              backgroundColor: Colors.grey[200],
                            ),
                            Center(
                              child: Text(
                                "${(_progressValue * 100).toInt()}%",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "AI가 음악을 분석 중입니다...🎧",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          _isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_fill,
                          size: 50,
                          color: Colors.deepPurple,
                        ),
                        onPressed: _togglePlay,
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton.icon(
                        onPressed: _getAiLyrics,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text("AI 가사 생성"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: _showLyricsDialog,
                      ),
                    ],
                  ),

            const Divider(height: 30),

            // 가사 리스트
            Expanded(
              child: _lyrics.isEmpty
                  ? const Center(child: Text("AI 가사 생성을 눌러보세요!"))
                  : ScrollablePositionedList.builder(
                      itemCount: _lyrics.length,
                      itemScrollController: _itemScrollController,
                      itemPositionsListener: _itemPositionsListener,
                      itemBuilder: (context, index) {
                        var line = _lyrics[index];
                        bool isActive = (index == _currentIndex);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 15,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.purple.withOpacity(0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 50,
                                child: Text(
                                  Duration(
                                    seconds: (line['start'] as num).toInt(),
                                  ).toString().split('.').first.substring(2, 7),
                                  style: TextStyle(
                                    color: isActive ? Colors.red : Colors.grey,
                                    fontWeight: isActive
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  line['text'],
                                  style: TextStyle(
                                    color: isActive
                                        ? Colors.red
                                        : Colors.black87,
                                    fontSize: isActive ? 22 : 16,
                                    fontWeight: isActive
                                        ? FontWeight.w900
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
