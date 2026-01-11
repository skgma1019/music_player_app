import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

// 🧠 전역 오디오 관리자 (싱글톤)
class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;
  AudioManager._internal();

  // 앱 전체에서 공유하는 단 하나의 플레이어
  final AudioPlayer player = AudioPlayer();

  // 현재 재생 목록 기억
  List<SongModel> currentPlaylist = [];
  
  // 초기화 및 재생 함수
  Future<void> playSong(List<SongModel> songs, int index) async {
    // 이미 같은 리스트가 로드되어 있고, 같은 곡을 누른 거면? -> 그냥 상세화면만 열면 됨 (재로딩 X)
    // 하지만 여기서는 리스트 갱신을 위해 항상 새로 로드하는 방식으로 구현
    currentPlaylist = songs;
    
    try {
      final playlist = ConcatenatingAudioSource(
        children: songs.map((song) {
          return AudioSource.file(
            song.data,
            tag: song, // 노래 정보 저장
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