import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../audio_manager.dart';
import 'lyrics_screen.dart';

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final AudioPlayer _audioPlayer = AudioManager().player;

  late ValueNotifier<int> _currentIndexNotifier;
  final ValueNotifier<List<Map<String, dynamic>>> _lyricsNotifier =
      ValueNotifier([]);
  final ValueNotifier<bool> _isAnalyzingNotifier = ValueNotifier(false);
  final ValueNotifier<double> _progressNotifier = ValueNotifier(0.0);

  bool _isPlaying = false;
  String _currentLyricLine = "가사가 없습니다 ㅠ";
  String _currentTransLine = ""; // 🌍 번역 가사 저장용
  String _manualLyrics = "";
  Timer? _progressTimer;

  final Map<String, String> _languages = {
    "자동 감지": "auto",
    "한국어": "ko",
    "영어": "en",
    "일본어": "ja",
  };
  String _selectedLanguage = "auto";

  @override
  void initState() {
    super.initState();
    _currentIndexNotifier = ValueNotifier<int>(_audioPlayer.currentIndex ?? 0);
    _setupAudioListeners();

    if (_audioPlayer.currentIndex != null) {
      _updateCurrentSongInfo(_audioPlayer.currentIndex!);
    }
  }

  void _setupAudioListeners() {
    _audioPlayer.currentIndexStream.listen((index) {
      if (index != null && mounted) {
        _currentIndexNotifier.value = index;
        _updateCurrentSongInfo(index);
      }
    });
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
    });
    _audioPlayer.positionStream.listen((p) => _updateCurrentLyricLine(p));
  }

  void _updateCurrentSongInfo(int index) {
    if (AudioManager().currentPlaylist.isEmpty ||
        index >= AudioManager().currentPlaylist.length)
      return;
    var song = AudioManager().currentPlaylist[index];

    setState(() {
      _currentLyricLine = "가사가 없습니다 ㅠ";
      _currentTransLine = "";
      _manualLyrics = "";
      if (globalLyricsCache.containsKey(song.id)) {
        _lyricsNotifier.value = globalLyricsCache[song.id]!;
      } else {
        _lyricsNotifier.value = [];
      }
    });
  }

  void _updateCurrentLyricLine(Duration position) {
    if (_lyricsNotifier.value.isEmpty) return;
    double currentSeconds = position.inMilliseconds / 1000.0;
    var match = _lyricsNotifier.value.lastWhere(
      (line) => (line['start'] as num).toDouble() <= currentSeconds,
      orElse: () => {},
    );

    if (match.isNotEmpty) {
      // 🌍 원문과 번역문 모두 업데이트
      if (match['text'] != _currentLyricLine) {
        setState(() {
          _currentLyricLine = match['text'];
          _currentTransLine = match['translated_text'] ?? ""; // 번역 없으면 빈칸
        });
      }
    }
  }

  void _playPrev() {
    if (_audioPlayer.hasPrevious)
      _audioPlayer.seekToPrevious();
    else
      _audioPlayer.seek(
        Duration.zero,
        index: AudioManager().currentPlaylist.length - 1,
      );
  }

  void _playNext() {
    if (_audioPlayer.hasNext)
      _audioPlayer.seekToNext();
    else
      _audioPlayer.seek(Duration.zero, index: 0);
  }

  void _togglePlay() {
    if (_isPlaying)
      _audioPlayer.pause();
    else
      _audioPlayer.play();
  }

  // 🔀 셔플 토글
  void _toggleShuffle() {
    final enable = !(_audioPlayer.shuffleModeEnabled);
    if (enable) {
      _audioPlayer.shuffle();
    }
    _audioPlayer.setShuffleModeEnabled(enable);
    setState(() {});
  }

  // 🔁 반복 모드 변경 (OFF -> ALL -> ONE)
  void _cycleLoopMode() {
    final current = _audioPlayer.loopMode;
    final next = current == LoopMode.off
        ? LoopMode.all
        : current == LoopMode.all
        ? LoopMode.one
        : LoopMode.off;
    _audioPlayer.setLoopMode(next);
    setState(() {});
  }

  void _showManualLyricsDialog() {
    TextEditingController controller = TextEditingController(
      text: _manualLyrics,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kAppWhite,
        title: const Text("가사 직접 입력"),
        content: SingleChildScrollView(
          child: TextField(
            controller: controller,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: "가사 입력",
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("취소"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _manualLyrics = controller.text);
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("저장됨")));
            },
            child: const Text("저장"),
          ),
        ],
      ),
    );
  }

  void _showAiLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String tempLanguage = _selectedLanguage;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: kAppWhite,
              title: const Text("언어 선택"),
              content: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: tempLanguage,
                  isExpanded: true,
                  items: _languages.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.value,
                          child: Text(e.key),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setStateDialog(() => tempLanguage = val!),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("취소"),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _selectedLanguage = tempLanguage);
                    Navigator.pop(context);
                    _requestAiLyrics();
                  },
                  child: const Text("생성 시작"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _requestAiLyrics() async {
    _isAnalyzingNotifier.value = true;
    _progressNotifier.value = 0.0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (_progressNotifier.value < 0.9) _progressNotifier.value += 0.05;
    });

    try {
      String baseUrl = "http://10.140.193.43:3000"; // ⚠️ 주소 확인
      var uri = Uri.parse("$baseUrl/analyze");
      var request = http.MultipartRequest('POST', uri);

      var song = AudioManager().currentPlaylist[_currentIndexNotifier.value];
      request.fields['language'] = _selectedLanguage;
      if (_manualLyrics.isNotEmpty)
        request.fields['lyrics_text'] = _manualLyrics;
      request.files.add(await http.MultipartFile.fromPath('audio', song.data));

      var response = await request.send();

      if (response.statusCode == 200) {
        var json = jsonDecode(await response.stream.bytesToString());
        List<Map<String, dynamic>> newLyrics = List<Map<String, dynamic>>.from(
          json['segments'],
        );
        _lyricsNotifier.value = newLyrics;
        _progressNotifier.value = 1.0;
        globalLyricsCache[song.id] = newLyrics;
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("가사 생성 완료! ✨")));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("에러: $e")));
    } finally {
      _progressTimer?.cancel();
      _isAnalyzingNotifier.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _currentIndexNotifier,
      builder: (context, currentIndex, child) {
        if (AudioManager().currentPlaylist.isEmpty) return const Scaffold();
        var song = AudioManager().currentPlaylist[currentIndex];

        return Scaffold(
          appBar: AppBar(
            title: Text(song.title, style: const TextStyle(fontSize: 16)),
            leading: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // 1. 앨범 아트
                        Container(
                          width: MediaQuery.of(context).size.width * 0.7,
                          height: MediaQuery.of(context).size.width * 0.7,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            color: kAppGrey,
                          ),
                          child: QueryArtworkWidget(
                            id: song.id,
                            type: ArtworkType.AUDIO,
                            nullArtworkWidget: const Icon(
                              Icons.music_note,
                              size: 80,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 2. 제목/가수
                        Column(
                          children: [
                            Text(
                              song.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              song.artist ?? "Unknown",
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // 3. 싱크 가사 바 (번역 포함)
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LyricsFullScreen(
                                  allSongs: AudioManager().currentPlaylist,
                                  audioPlayer: _audioPlayer,
                                  currentIndexNotifier: _currentIndexNotifier,
                                  lyricsNotifier: _lyricsNotifier,
                                  onPrev: _playPrev,
                                  onNext: _playNext,
                                  onPlayPause: _togglePlay,
                                  onShowAiModal: _showAiLanguageDialog,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: kAppGrey,
                              border: Border.all(color: Colors.grey),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  _currentLyricLine,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                if (_currentTransLine
                                    .isNotEmpty) // 번역이 있을 때만 표시
                                  Text(
                                    _currentTransLine,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.blueAccent,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 4. 슬라이더
                        StreamBuilder<Duration>(
                          stream: _audioPlayer.positionStream,
                          builder: (context, snapshot) {
                            final position = snapshot.data ?? Duration.zero;
                            final total =
                                _audioPlayer.duration ?? Duration.zero;
                            return Column(
                              children: [
                                Slider(
                                  activeColor: kAppBlack,
                                  inactiveColor: Colors.grey,
                                  thumbColor: kAppBlack,
                                  min: 0,
                                  max: total.inSeconds.toDouble() > 0
                                      ? total.inSeconds.toDouble()
                                      : 1.0,
                                  value: position.inSeconds.toDouble().clamp(
                                    0,
                                    total.inSeconds.toDouble(),
                                  ),
                                  onChanged: (val) => _audioPlayer.seek(
                                    Duration(seconds: val.toInt()),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        position
                                            .toString()
                                            .split('.')
                                            .first
                                            .padLeft(8, "0")
                                            .substring(3),
                                      ),
                                      Text(
                                        total
                                            .toString()
                                            .split('.')
                                            .first
                                            .padLeft(8, "0")
                                            .substring(3),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 10),

                        // 5. 컨트롤러 (셔플 & 반복 추가됨)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // 🔀 셔플 버튼
                            IconButton(
                              icon: Icon(
                                Icons.shuffle,
                                color: _audioPlayer.shuffleModeEnabled
                                    ? kAppYellow
                                    : Colors.grey,
                              ),
                              onPressed: _toggleShuffle,
                            ),

                            IconButton(
                              icon: const Icon(Icons.arrow_back, size: 40),
                              onPressed: _playPrev,
                            ),

                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: kAppBlack),
                              ),
                              child: IconButton(
                                icon: Icon(
                                  _isPlaying ? Icons.pause : Icons.play_arrow,
                                  size: 40,
                                ),
                                onPressed: _togglePlay,
                              ),
                            ),

                            IconButton(
                              icon: const Icon(Icons.arrow_forward, size: 40),
                              onPressed: _playNext,
                            ),

                            // 🔁 반복 버튼 (아이콘 변경됨)
                            IconButton(
                              icon: Icon(
                                _audioPlayer.loopMode == LoopMode.one
                                    ? Icons.repeat_one
                                    : Icons.repeat,
                                color: _audioPlayer.loopMode == LoopMode.off
                                    ? Colors.grey
                                    : kAppYellow,
                              ),
                              onPressed: _cycleLoopMode,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // 6. 하단 버튼
                        ValueListenableBuilder<bool>(
                          valueListenable: _isAnalyzingNotifier,
                          builder: (context, isAnalyzing, child) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton(
                                  onPressed: _showManualLyricsDialog,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kAppGrey,
                                  ),
                                  child: const Text("가사 넣기"),
                                ),
                                if (isAnalyzing)
                                  const CircularProgressIndicator()
                                else
                                  ElevatedButton(
                                    onPressed: _showAiLanguageDialog,
                                    child: const Text("AI 가사 생성"),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
