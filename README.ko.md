<div align="center">

# Nib

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-macOS-111827?logo=apple&logoColor=white)
![Type](https://img.shields.io/badge/type-Markdown%20Editor-2563eb)
![Size](https://img.shields.io/badge/size-1.4MB-059669)

</div>

Nib은 macOS를 위한 미니멀 Markdown 편집기입니다. 크기는 **약 1.4MB** —— Typora는 46MB, Electron 편집기는 보통 150-250MB입니다.

CodeMirror 6을 감싼 네이티브 Swift 셸입니다. 바로 열리고, 방해하지 않으며, 작은 편집기에서는 보기 드문 기능을 하나 갖고 있습니다. 고스트 라이팅입니다.

의미가 끊기는 지점 —— 문장의 끝, 새로운 줄, 새로운 목록 항목 —— 에서 당신의 LLM이 회색 이어쓰기를 제안합니다. Tab으로 수락하고 Esc로 닫습니다. 키를 누를 때마다 뜨지 않고, 삭제 중이거나 실행 취소 중이거나 선택 영역이 있을 때는 절대 나타나지 않습니다.

```
주전자는 한참 전부터 올려둔 채였고,
                                  ▏창문에는 김이 서려 있었다.   ← Tab으로 수락
```

모델은 내장되어 있지 않습니다. 직접 모델을 연결하고, 키는 키체인 밖으로 나가지 않습니다.

## Nib을 선택하는 이유

- 🪶 **1.4MB**: 제목 표시줄을 씌운 브라우저가 아니라 진짜 네이티브 앱입니다.
- ✍️ **고스트 라이팅**: 단어 중간이 아니라 생각이 한 번 끊긴 자리에 제안이 나타납니다.
- 🔌 **내 모델 사용**: Anthropic과 OpenAI 프로토콜을 지원 —— Base URL만 바꾸면 자체 호스팅한 vLLM, Ollama, LM Studio도 그대로 쓸 수 있습니다.
- 🔒 **키는 키체인에**: 요청은 Swift에서 보내므로 키가 JavaScript 영역으로 들어가지 않습니다.
- 📄 **두 가지 모드**: 소스와 미리 보기를 `Cmd+/`로 전환합니다. 미리 보기에서는 구조적으로 고스트 라이팅이 실행될 수 없습니다.
- 🖼️ **옮겨도 깨지지 않는 이미지**: 붙여넣은 이미지는 문서 옆 `<document>.assets/` 폴더에 상대 링크로 저장되어, 폴더를 옮기거나 동기화해도 링크가 유지됩니다.
- 🗂️ **사이드바**: 파일 트리, 아웃라인, 파일 간 검색.
- 🆓 **무료, MIT 라이선스**.

<!-- TODO: add screenshots of the editor, ghost text in action, and Settings -->

## 설치

[릴리스 페이지](https://github.com/howtoexitvim/Nib/releases)에서 zip을 내려받고(현재 릴리스 **v0.1.0**), 압축을 푼 뒤 `Nib.app`을 `/Applications`로 끌어다 놓으세요.

이 빌드는 ad-hoc 서명이며 공증되지 않았습니다. 그래서 격리 플래그를 한 번 해제해야 합니다:

```bash
xattr -dr com.apple.quarantine /Applications/Nib.app
```

Apple 실리콘만 지원합니다.

## 자동 완성 설정

설정 항목은 네 가지입니다: Provider, Base URL, Model, API key.

공식 API를 쓸 때는 Anthropic이나 OpenAI를 고르고 Base URL은 기본값 그대로 두면 됩니다. 자체 호스팅한 OpenAI 호환 서버를 쓸 때는 OpenAI를 고른 뒤 Base URL을 자신의 엔드포인트로 지정하세요. 예를 들면 `http://127.0.0.1:8000/v1`입니다. 서버에 인증이 없다면 키는 비워 두어도 됩니다.

요청에는 `chat_template_kwargs: {"enable_thinking": false}`가 포함되어, reasoning parser를 쓰는 모델에서도 완성 결과가 정상적으로 돌아옵니다.

## 빌드

```bash
make        # web 번들과 build/Nib.app 빌드
make run    # 빌드 후 실행
make test   # Swift 테스트 + JS 테스트
```

Xcode 프로젝트는 필요 없습니다 —— Swift 툴체인과 Node만 있으면 됩니다. 테스트는 Swift 81개, JS 75개입니다.

## 프로젝트

프로젝트 홈: https://github.com/howtoexitvim/Nib

## License

[MIT](LICENSE)
