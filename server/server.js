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
  const userLanguage = req.body.language || "auto";
  const userLyrics = req.body.lyrics_text;
  console.log("📥 [Node] Flutter로부터 파일 수신 / 언어설정:", userLanguage);

  try {
    if (!req.file) {
      return res.status(400).send("파일이 없습니다.");
    }

    // 1. Python 서버(8000번)로 보낼 폼 데이터 준비
    const formData = new FormData();
    const filePath = path.join(__dirname, req.file.path);

    // Python에게 'file'이라는 이름으로 전송
    formData.append("file", fs.createReadStream(filePath));
    formData.append("Language", fs.createReadStream(filePath));
    if (userLyrics) {
      console.log("📝 [Node] 사용자 입력 가사 전달 중...");
      formData.append("lyrics_text", userLyrics);
    }
    console.log("🔄 [Node] Python AI 서버로 분석 요청 중...");

    // 2. Python 서버에게 요청 (30초 타임아웃 설정)
    const response = await axios.post(
      "http://127.0.0.1:8000/analyze",
      formData,
      {
        headers: { ...formData.getHeaders() },
        timeout: 300000, // 30초
      }
    );

    console.log("✅ [Node] 분석 완료! Flutter에게 결과 전달.");

    // 3. 임시 파일 삭제 (청소)
    fs.unlinkSync(filePath);

    // 4. 결과 반환 (JSON)
    res.json(response.data);
  } catch (error) {
    console.error("❌ 에러 발생:", error.message);
    res.status(500).send("AI 서버 연결 실패 또는 분석 오류");

    // 에러 나도 임시 파일은 지워주기
    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
  }
});

app.listen(3000, () => {
  console.log("🚀 Node.js 서버가 3000번 포트에서 대기 중입니다.");
});
