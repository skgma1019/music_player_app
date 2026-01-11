import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio/just_audio.dart';
import '../constants.dart';
import '../audio_manager.dart'; // 오디오 본부
import 'music_player_screen.dart';

class SongListScreen extends StatefulWidget {
  const SongListScreen({super.key});

  @override
  State<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends State<SongListScreen> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioManager _audioManager = AudioManager(); // 싱글톤 인스턴스
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    if (await Permission.audio.request().isGranted ||
        await Permission.storage.request().isGranted) {
      setState(() => _hasPermission = true);
    }
  }

  Future<List<SongModel>> _getMusicFiles() async {
    List<SongModel> allSongs = await _audioQuery.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    return allSongs.where((song) {
      String path = song.data.toLowerCase();
      String title = song.displayName.toLowerCase();
      return !(path.contains('/call/') || title.startsWith('call_'));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Music App")),
      // 🛠️ Stack: 리스트 위에 미니 플레이어를 얹기 위해 사용
      body: Stack(
        children: [
          // 1. 노래 리스트 (뒤쪽)
          !_hasPermission
              ? Center(child: ElevatedButton(onPressed: _checkPermission, child: const Text("권한 허용")))
              : FutureBuilder<List<SongModel>>(
                  future: _getMusicFiles(),
                  builder: (context, item) {
                    if (item.data == null) return const Center(child: CircularProgressIndicator());
                    if (item.data!.isEmpty) return const Center(child: Text("노래 없음"));

                    List<SongModel> songs = item.data!;
                    return ListView.builder(
                      // 미니 플레이어(80px)에 가려지지 않게 아래 여백 추가
                      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100),
                      itemCount: songs.length,
                      itemBuilder: (context, index) {
                        var song = songs[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: kAppGrey,
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListTile(
                            leading: QueryArtworkWidget(id: song.id, type: ArtworkType.AUDIO, nullArtworkWidget: const Icon(Icons.music_note)),
                            title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(song.artist ?? "Unknown", maxLines: 1),
                            onTap: () {
                              // 🎵 리스트 클릭 시 재생 시작
                              _audioManager.playSong(songs, index);
                              // 상세 화면으로 이동
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const MusicPlayerScreen()),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),

          // 2. 미니 플레이어 (앞쪽, 바닥 고정)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: StreamBuilder<int?>(
              stream: _audioManager.player.currentIndexStream,
              builder: (context, snapshot) {
                final index = snapshot.data;
                // 재생 중인 노래가 없으면 숨김
                if (index == null || _audioManager.currentPlaylist.isEmpty) return const SizedBox.shrink();

                // 현재 재생 중인 노래 정보 가져오기
                final song = _audioManager.currentPlaylist[index];

                return GestureDetector(
                  onTap: () {
                    // 미니 플레이어 클릭 -> 상세 화면 열기
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const MusicPlayerScreen()),
                    );
                  },
                  child: Container(
                    height: 80,
                    margin: const EdgeInsets.all(10),
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: BoxDecoration(
                      color: kAppBlack, // 배경 검정
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 10)],
                      border: Border.all(color: kAppYellow, width: 1), // 테두리 노랑
                    ),
                    child: Row(
                      children: [
                        // 앨범 아트
                        Container(
                          width: 50, height: 50,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.grey),
                          child: QueryArtworkWidget(
                            id: song.id, type: ArtworkType.AUDIO,
                            artworkFit: BoxFit.cover,
                            nullArtworkWidget: const Icon(Icons.music_note, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 15),
                        // 제목 & 가수
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: kAppWhite, fontWeight: FontWeight.bold, fontSize: 16)),
                              Text(song.artist ?? "Unknown", maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: kAppYellow, fontSize: 12)),
                            ],
                          ),
                        ),
                        // 재생/멈춤 버튼
                        StreamBuilder<PlayerState>(
                          stream: _audioManager.player.playerStateStream,
                          builder: (context, snapshot) {
                            final isPlaying = snapshot.data?.playing ?? false;
                            return IconButton(
                              icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                              color: kAppYellow,
                              iconSize: 45,
                              onPressed: () {
                                if (isPlaying) _audioManager.player.pause();
                                else _audioManager.player.play();
                              },
                            );
                          },
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}