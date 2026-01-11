import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../constants.dart';

class LyricsFullScreen extends StatefulWidget {
  final List<SongModel> allSongs;
  final AudioPlayer audioPlayer;
  
  // 📡 데이터 공유용 Notifier (부모가 줌)
  final ValueNotifier<int> currentIndexNotifier;
  final ValueNotifier<List<Map<String, dynamic>>> lyricsNotifier;

  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPlayPause;
  final VoidCallback onShowAiModal; // [Issue 6] 모달 띄우기 함수

  const LyricsFullScreen({
    super.key,
    required this.allSongs,
    required this.audioPlayer,
    required this.currentIndexNotifier,
    required this.lyricsNotifier,
    required this.onPrev,
    required this.onNext,
    required this.onPlayPause,
    required this.onShowAiModal,
  });

  @override
  State<LyricsFullScreen> createState() => _LyricsFullScreenState();
}

class _LyricsFullScreenState extends State<LyricsFullScreen> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  int _highlightedLineIndex = -1; // 현재 부르고 있는 가사 줄 인덱스
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.audioPlayer.playing;

    // 가사 스크롤 싱크 로직
    widget.audioPlayer.positionStream.listen((p) {
      if (!mounted) return;
      // 현재 가사 리스트 가져오기
      var currentLyrics = widget.lyricsNotifier.value;
      if (currentLyrics.isEmpty) return;

      double currentSeconds = p.inMilliseconds / 1000.0;
      int foundIndex = -1;

      for (int i = 0; i < currentLyrics.length; i++) {
        if ((currentLyrics[i]['start'] as num).toDouble() <= currentSeconds) {
          foundIndex = i;
        } else {
          break;
        }
      }

      if (foundIndex != -1 && foundIndex != _highlightedLineIndex) {
        setState(() => _highlightedLineIndex = foundIndex);
        _scrollToIndex(foundIndex);
      }
    });

    widget.audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
    });
  }

  void _scrollToIndex(int index) {
    if (_itemScrollController.isAttached) {
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 📡 노래 인덱스가 바뀌면 화면을 다시 그림
    return ValueListenableBuilder<int>(
      valueListenable: widget.currentIndexNotifier,
      builder: (context, currentIndex, _) {
        var song = widget.allSongs[currentIndex];

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                Container(
                  width: 40, height: 40, margin: const EdgeInsets.only(right: 10), color: kAppGrey,
                  child: QueryArtworkWidget(id: song.id, type: ArtworkType.AUDIO, nullArtworkWidget: const Icon(Icons.music_note)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      Text(song.artist ?? "Unknown", overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                )
              ],
            ),
            actions: [
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))
            ],
          ),
          body: Column(
            children: [
              // 가사 리스트 영역
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: kAppGrey, border: Border.all(color: Colors.grey)),
                  
                  // 📡 가사 데이터가 바뀌면 리스트 다시 그림
                  child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                    valueListenable: widget.lyricsNotifier,
                    builder: (context, lyrics, _) {
                      if (lyrics.isEmpty) {
                        return const Center(child: Text("가사가 없습니다."));
                      }
                      return ScrollablePositionedList.builder(
                        itemScrollController: _itemScrollController,
                        itemCount: lyrics.length,
                        itemBuilder: (context, index) {
                          bool isActive = index == _highlightedLineIndex;
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                            alignment: Alignment.center,
                            child: Text(
                              lyrics[index]['text'],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isActive ? Colors.black : Colors.grey,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                fontSize: isActive ? 20 : 16,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              // 컨트롤러
              Container(
                padding: const EdgeInsets.only(bottom: 30, top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(icon: const Icon(Icons.arrow_back, size: 40), onPressed: widget.onPrev),
                    const SizedBox(width: 20),
                    Container(
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kAppBlack)),
                      child: IconButton(
                        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 40), 
                        onPressed: widget.onPlayPause
                      ),
                    ),
                    const SizedBox(width: 20),
                    IconButton(icon: const Icon(Icons.arrow_forward, size: 40), onPressed: widget.onNext),
                  ],
                ),
              ),

              // 하단 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () {}, // 가사 넣기 모달도 필요하면 부모 함수 받아오기 가능
                    style: ElevatedButton.styleFrom(backgroundColor: kAppGrey), 
                    child: const Text("가사 넣기"),
                  ),
                  ElevatedButton(
                    onPressed: widget.onShowAiModal, // [Issue 6 해결] 바로 모달 띄우기
                    child: const Text("AI 가사 생성"),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}