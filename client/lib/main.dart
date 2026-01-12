import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart'; // ⬅️ 추가됨
import 'constants.dart';
import 'screens/song_list_screen.dart';

// main 함수를 Future<void>와 async로 변경해야 초기화 코드를 기다릴 수 있습니다.
Future<void> main() async {
  // 1. 플러터 엔진과 위젯 바인딩을 미리 초기화 (비동기 작업 필수)
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 백그라운드 오디오 서비스 초기화
  await JustAudioBackground.init(
    androidNotificationChannelId:
        'com.ryanheise.bg_demo.channel.audio', // 알림 채널 ID (고유해야 함)
    androidNotificationChannelName: 'Audio playback', // 사용자에게 보이는 알림 채널 이름
    androidNotificationOngoing: true, // 앱이 실행 중일 때 알림 유지
  );

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: kAppWhite,
        primaryColor: kAppYellow,
        appBarTheme: const AppBarTheme(
          backgroundColor: kAppWhite,
          foregroundColor: kAppBlack,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: kAppBlack,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kAppYellow, // 버튼 배경 노랑
            foregroundColor: kAppBlack, // 버튼 글자 검정
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: kAppBlack, width: 1),
            ),
          ),
        ),
      ),
      home: const SongListScreen(),
    ),
  );
}
