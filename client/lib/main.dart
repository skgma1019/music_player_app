import 'package:flutter/material.dart';
import 'constants.dart';
import 'screens/song_list_screen.dart';

void main() {
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
              color: kAppBlack, fontSize: 24, fontWeight: FontWeight.bold),
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