const express = require("express");
const cors = require("cors");
const multer = require("multer");
const axios = require("axios");
const FormData = require("form-data");
const fs = require("fs");
const path = require("path");

// 파일 업로드 설정 (uploads 폴더에 임시 저장)
const upload = multer({ dest: "uploads/" });

const app = express();
app.use(cors());

// uploads 폴더가 없으면 생성
if (!fs.existsSync("uploads")) {
  fs.mkdirSync("uploads");
}

// 🎯 핵심 API: Flutter가 이 주소로 파일을 보냅니다.
app.post("/analyze", upload.single("audio"), async (req, res) => {
  // Flutter에서 보낸 언어 설정을 받습니다. (없으면 'auto')
  const userLanguage = req.body.language || "auto"; 
  const userLyrics = req.body.lyrics_text;
  
  console.log(`📥 [Node] Flutter 수신 완료 | 언어: ${userLanguage}`);

  try {
    if (!req.file) {
      return res.status(400).send("파일이 없습니다.");
    }

    // 1. Python 서버(8000번)로 보낼 폼 데이터 준비
    const formData = new FormData();
    const filePath = path.join(__dirname, req.file.path);

    // ⬇️ [수정됨] Python에게 보낼 데이터 포장 (매우 중요!)
    // Python의 main.py: file, language, lyrics_text 이름을 기다림
    formData.append("file", fs.createReadStream(filePath));
    formData.append("language", userLanguage); // 👈 수정: 대문자 L -> 소문자 l, 값은 변수 사용

    if (userLyrics) {
      console.log("📝 [Node] 사용자 입력 가사 전달 중...");
      formData.append("lyrics_text", userLyrics);
    }
    
    console.log("🔄 [Node] Python AI 서버로 분석 요청 중...");

    // 2. Python 서버에게 요청 (타임아웃 5분 넉넉히)
    // Node와 Python이 같은 컴퓨터라면 127.0.0.1이 가장 안전합니다.
    const response = await axios.post(
      "http://127.0.0.1:8000/analyze", 
      formData,
      {
        headers: { ...formData.getHeaders() },
        timeout: 300000, // 300초 (5분)
        maxContentLength: Infinity,
        maxBodyLength: Infinity
      }
    );

    console.log("✅ [Node] 분석 완료! Flutter에게 결과 전달.");

    // 3. 임시 파일 삭제 (청소)
    if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
    }

    // 4. 결과 반환 (JSON)
    res.json(response.data);

  } catch (error) {
    console.error("❌ [Node] 에러 발생:", error.message);
    if (error.response) {
        console.error("   Python 응답 코드:", error.response.status);
        console.error("   Python 에러 내용:", error.response.data);
    }

    res.status(500).send("AI 서버 연결 실패 또는 분석 오류");

    // 에러 나도 임시 파일은 지워주기
    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
  }
});

app.listen(3000, "0.0.0.0", () => {
  console.log("🚀 Node.js 서버가 3000번 포트에서 대기 중입니다.");
});