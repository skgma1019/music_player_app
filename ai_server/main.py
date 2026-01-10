from fastapi import FastAPI, UploadFile, File, Form
from fastapi.responses import JSONResponse
import whisper
import shutil
import os
import re
import traceback
import subprocess

app = FastAPI()

# 모델 로드
print("⏳ 모델 로딩 중... (Small)")
model = whisper.load_model("small")
print("✅ 모델 로딩 완료!")

# 🛠️ [기존 유지] FFmpeg가 어디에 있든 찾아내는 똑똑한 함수
def get_ffmpeg_command():
    # 1. Choco로 설치된(시스템에 깔린) ffmpeg가 있는지 확인
    if shutil.which("ffmpeg"):
        print("🔧 [도구 발견] 시스템 기본(Choco 등) ffmpeg 사용")
        return "ffmpeg"
    
    # 2. 없다면, 내 폴더(ai_server) 안에 exe가 있는지 확인
    current_dir = os.path.dirname(os.path.abspath(__file__))
    local_ffmpeg = os.path.join(current_dir, "ffmpeg.exe")
    
    if os.path.exists(local_ffmpeg):
        print(f"🔧 [도구 발견] 로컬 폴더 내 ffmpeg 사용: {local_ffmpeg}")
        return local_ffmpeg
    
    # 3. 둘 다 없으면 에러
    raise FileNotFoundError("FFmpeg를 찾을 수 없습니다. (Choco 설치 또는 exe 파일 복사 필요)")

def convert_to_clean_wav(input_path):
    try:
        command_executable = get_ffmpeg_command()
        output_path = os.path.splitext(input_path)[0] + "_clean.wav"
        print(f"🔄 [변환 시작] {input_path} -> {output_path}")
        
        command = [
            command_executable, 
            "-i", input_path,
            "-ar", "16000",
            "-ac", "1",
            "-c:a", "pcm_s16le",
            "-vn",
            "-y",
            output_path
        ]
        
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        print("✅ [변환 완료] 깨끗한 WAV 파일 생성됨")
        return output_path

    except Exception as e:
        print(f"🚨 변환 실패 (원본 사용): {e}")
        return input_path 

# 🛠️ [추가] AI가 뱉은 환각(Lyrics, MBC 등) 청소하는 함수
def clean_hallucinations(segments):
    cleaned = []
    # 지워버릴 금지어 리스트 (소문자로 작성)
    banned_words = ["lyrics", "lyrics.", "노래 가사", "mbc", "subtitles", "sous-titres", "시청해 주셔서 감사합니다"]
    
    for seg in segments:
        text = seg['text'].strip()
        
        # 1. 내용이 아예 없으면 패스
        if not text: continue
        
        # 2. 금지어와 똑같으면 패스 (대소문자 무시)
        if text.lower() in banned_words:
            continue
            
        # 3. 특수문자만 있는 경우 패스 (예: "...")
        if re.match(r'^[\W_]+$', text):
            continue

        cleaned.append(seg)
        
    return cleaned

# 1. 일반적인 LRC 파싱
def parse_lrc_with_timestamp(lrc_content: str):
    segments = []
    pattern = re.compile(r'\[?(\d+):(\d+\.?\d*)\]?\s*(.*)')
    
    for line in lrc_content.splitlines():
        line = line.strip()
        if not line: continue
        match = pattern.match(line)
        if match:
            minutes = int(match.group(1))
            seconds = float(match.group(2))
            text = match.group(3).strip()
            total_seconds = minutes * 60 + seconds
            if text:
                segments.append({"start": total_seconds, "text": text})
    return segments

# 2. 강제 싱크 맞춤
def force_align_lyrics(whisper_result, user_text):
    ai_timestamps = [seg['start'] for seg in whisper_result['segments']]
    user_lines = [line.strip() for line in user_text.splitlines() if line.strip()]
    
    if not ai_timestamps or not user_lines: return []

    final_segments = []
    if not whisper_result['segments']: return [] 

    total_ai_duration = whisper_result['segments'][-1]['end'] - whisper_result['segments'][0]['start']
    start_offset = whisper_result['segments'][0]['start']
    count = len(user_lines)
    
    for i, line in enumerate(user_lines):
        percent = i / count 
        calculated_time = start_offset + (total_ai_duration * percent)
        calculated_time = round(calculated_time, 2)
        final_segments.append({"start": calculated_time, "text": line})
        
    return final_segments

@app.post("/analyze")
async def analyze_audio(
    file: UploadFile = File(...), 
    language: str = Form("auto"), 
    lyrics_text: str = Form(None)
):
    temp_filename = f"temp_{file.filename}"
    clean_audio_path = None
    
    actual_language = None if language == "auto" else language

    print(f"\n🚀 [요청] {file.filename} / 언어: {actual_language if actual_language else '자동'}")

    try:
        # 1. 원본 저장
        with open(temp_filename, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        # 2. 변환 시도 (Choco or 로컬 파일)
        clean_audio_path = convert_to_clean_wav(temp_filename)

        # A. 사용자 가사 있음
        if lyrics_text:
            print(f"📝 사용자 가사 수신됨 (길이: {len(lyrics_text)})")
            
            parsed = parse_lrc_with_timestamp(lyrics_text)
            if len(parsed) > 0:
                print("✨ 시간 정보 포함됨 -> 바로 적용")
                if os.path.exists(temp_filename): os.remove(temp_filename)
                if clean_audio_path != temp_filename and os.path.exists(clean_audio_path): 
                    os.remove(clean_audio_path)
                return JSONResponse(content={"segments": parsed})
            
            print("💡 텍스트만 있음 -> AI로 시간 추출")
            raw_result = model.transcribe(clean_audio_path, language=actual_language, fp16=False)
            aligned_result = force_align_lyrics(raw_result, lyrics_text)
            
            print(f"✅ 매핑 완료: 총 {len(aligned_result)}줄")
            
            if os.path.exists(temp_filename): os.remove(temp_filename)
            if clean_audio_path != temp_filename and os.path.exists(clean_audio_path): 
                os.remove(clean_audio_path)
            return JSONResponse(content={"segments": aligned_result})

        # B. 가사 없음 (환각 방지 기능 추가됨)
        else:
            print(f"🤖 가사 없음 -> AI 받아쓰기 모드")
            
            # ⬇️ [수정] 환각 방지 옵션 적용
            result = model.transcribe(
                clean_audio_path, 
                language=actual_language,
                initial_prompt="Hello, this is a song.", # 힌트 변경
                fp16=False,
                condition_on_previous_text=False, # 앵무새 방지
                no_speech_threshold=0.6, # 잡음 무시
                logprob_threshold=-1.0   # 확신 없으면 버림
            )

            # ⬇️ [추가] 쓰레기 값 청소
            result['segments'] = clean_hallucinations(result['segments'])
            
            if os.path.exists(temp_filename): os.remove(temp_filename)
            if clean_audio_path != temp_filename and os.path.exists(clean_audio_path): 
                os.remove(clean_audio_path)
                
            return JSONResponse(content=result)

    except Exception as e:
        print(f"\n💥 에러 발생: {traceback.format_exc()}")
        if os.path.exists(temp_filename): os.remove(temp_filename)
        if clean_audio_path and clean_audio_path != temp_filename and os.path.exists(clean_audio_path): 
            os.remove(clean_audio_path)
        return JSONResponse(content={"error": str(e)}, status_code=500)