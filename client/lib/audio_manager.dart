import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart'; // 추가
import 'package:on_audio_query/on_audio_query.dart';

class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;
  AudioManager._internal();

  final AudioPlayer player = AudioPlayer();
  List<SongModel> currentPlaylist = [];

  Future<void> playSong(List<SongModel> songs, int index) async {
    currentPlaylist = songs;

    try {
      final playlist = ConcatenatingAudioSource(
        children: songs.map((song) {
          return AudioSource.file(
            song.data,
            // 🏷️ [핵심] 잠금화면에 띄울 정보 (MediaItem)
            tag: MediaItem(
              id: song.id.toString(),
              album: song.album ?? "Unknown Album",
              title: song.title,
              artist: song.artist ?? "Unknown Artist",
              artUri: null, // 앨범 아트 URI가 있다면 넣을 수 있음
            ),
          );
        }).toList(),
      );

      await player.setAudioSource(
        playlist,
        initialIndex: index,
        initialPosition: Duration.zero,
      );

      player.play();
    } catch (e) {
      print("재생 실패: $e");
    }
  }
}
