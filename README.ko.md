<div align="center">

# Nib

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-macOS-111827?logo=apple&logoColor=white)
![Type](https://img.shields.io/badge/type-Markdown%20Editor-2563eb)
![Size](https://img.shields.io/badge/size-1.4MB-059669)

</div>

Nib은 macOS용 미니멀 마크다운 에디터입니다. 네이티브 Swift 셸이 WKWebView 하나를 감싸고, 그 안에서 CodeMirror 6이 동작합니다.

**ghost writing** 기능이 있습니다. 문장 끝, 줄바꿈, 새 목록 항목처럼 의미의 경계에서 직접 설정한 LLM이 이어질 내용을 회색으로 제안합니다. Tab으로 수락하고 Esc로 무시합니다. 제공자는 직접 설정하며, 내장된 모델은 없습니다.

API 키는 Keychain에 저장되고 요청은 Swift 쪽에서 발생하므로, 키가 JavaScript 컨텍스트에 들어가는 일은 없습니다.

## 설치

[releases 페이지](https://github.com/howtoexitvim/Nib/releases)에서 zip을 내려받아 압축을 풀고 `Nib.app`을 `/Applications`로 끌어다 놓으세요. 빌드는 ad-hoc 서명이고 공증(notarize)되지 않았으므로, 한 번 격리 플래그를 지워야 합니다.

```bash
xattr -dr com.apple.quarantine /Applications/Nib.app
```

Apple 실리콘(arm64)만 지원합니다. 최신 릴리스는 **v0.1.0**입니다.

직접 소스에서 빌드할 수도 있습니다. Swift 툴체인과 Node만 있으면 됩니다.

## 빌드

```bash
make        # web 번들과 build/Nib.app 빌드
make run    # 빌드 후 실행
make test   # Swift 테스트 + JS 테스트
make clean
```

Xcode 프로젝트는 없습니다. `swift build`가 바이너리를 만들고 Makefile이 `.app`을 직접 조립하므로, 전 과정을 커맨드라인에서 재현할 수 있습니다.

결과물은 약 **1.4MB**입니다(Typora는 46MB, Electron 앱은 보통 150-250MB).

## 두 가지 모드

소스 모드는 CodeMirror이고, 미리보기 모드는 읽기 전용 렌더링입니다. **소스만이 유일한 진실이고, 미리보기는 그 투영입니다.** `Cmd+/`로 전환하며, 단축키는 window에 바인딩되어 있어 두 모드 모두에서 동작합니다.

미리보기는 편집이 불가능하고 입력도 처리하지 않으므로, 미리보기 모드에서는 ghost text가 발동할 **코드 경로 자체가 없습니다**. `if` 문으로 막은 것이 아니라 구조적으로 그렇습니다.

## Ghost writing

- **의미의 경계**에서만 발동합니다(문장 끝, 절의 끝, 줄바꿈, 새 목록 항목). 매 키 입력마다가 아닙니다. 전각 문장부호도 포함됩니다.
- 삭제, 실행 취소, 다시 실행, 다중 커서, 선택 영역이 있을 때는 발동하지 않습니다.
- 500ms 디바운스, 앞뒤 각각 4000자의 컨텍스트(fill-in-the-middle), `(prefix, suffix)` 기준으로 캐시합니다.
- Tab으로 수락, Esc로 무시. 계속 입력한 내용이 제안과 일치하면 제안이 유지되며 앞으로 진행됩니다.

## 자동 완성 설정

설정에는 네 가지 항목이 있습니다. Provider, Base URL, Model, API 키입니다.

공식 API를 쓴다면 Anthropic 또는 OpenAI를 고르고 Base URL은 기본값으로 두세요.

자체 호스팅한 OpenAI 호환 서버(vLLM, Ollama, LM Studio)를 쓴다면 **OpenAI**를 고르고 Base URL을 자신의 엔드포인트로 지정하세요. 예를 들어 `http://127.0.0.1:8000/v1`입니다. 서버에 인증이 없다면 키는 비워 두어도 되고, 인증이 있다면 키가 반드시 필요하며 없으면 `Unauthorized`가 반환됩니다.

**reasoning 모델에 관한 주의.** vLLM을 `--reasoning-parser`와 함께 실행하면 사고 과정이 `reasoning` 필드로 들어가고 `content`는 `null`로 돌아옵니다. 짧은 완성의 토큰 예산이 전부 사고에 쓰여서 ghost text는 아무것도 받지 못합니다. 그래서 요청 본문에는 항상 `chat_template_kwargs: {"enable_thinking": false}`를 담습니다. 공식 OpenAI API는 알 수 없는 최상위 필드를 무시하므로 그쪽에서는 해가 없습니다.

지원하는 프로토콜은 **Anthropic**과 **OpenAI** 둘뿐입니다. 후자는 vLLM, Ollama, LM Studio가 노출하는 인터페이스 그 자체이므로, 로컬 모델을 위해 별도의 코드가 필요하지 않습니다. base URL만 그쪽으로 돌리면 됩니다.

## 설계 노트

**창 하나, WebView 하나.** `WKWebView`는 각각 독립된 content process(30-60MB)입니다. 파일마다 창을 여는 방식은 파일이 수백 개인 노트 보관함에서 버티지 못합니다. 그래서 파일 전환은 내용을 바꾸는 방식으로 처리합니다.

**파일을 전환할 때 transaction을 dispatch하지 않고 `EditorState`를 다시 만듭니다.** transaction은 undo history를 유지하기 때문에, A에서 B로 옮긴 뒤 `Cmd+Z`를 누르면 A의 텍스트가 B로 끌려 들어오고 다음 저장에서 B가 망가집니다. 대가로 파일을 넘나드는 undo는 없습니다.

**파일 트리는 지연 로딩입니다.** 실제 노트 디렉터리(폴더 6,165개 / `.md` 1,599개)를 전부 재귀 탐색하면 측정값이 0.81초였고, 창을 여는 경로에 두면 눈에 보이는 끊김이 됩니다. 한 단계만 읽으면 2ms입니다.

**붙여넣은 이미지는 `<문서명>.assets/`에 저장되고**(Typora의 관례) 상대 경로로 링크됩니다. 폴더째 옮기거나 동기화하거나 공유해도 링크가 그대로 유효합니다. 종류는 클립보드가 주장하는 값이 아니라 **바이트**로 판별합니다. 둘이 어긋나는 경우가 적지 않고, 확장자가 실제 내용과 맞지 않으면 아무것도 렌더링되지 않기 때문입니다. macOS 스크린샷은 TIFF로 들어오므로 PNG로 변환합니다.

미리보기의 이미지는 `nib-asset://`을 거쳐 Swift가 바이트를 읽습니다. 그렇지 않으면 상대 경로가 번들 기준으로 해석되고, 게다가 페이지의 읽기 권한은 번들의 `web/`에만 미칩니다. `<base>` 태그는 선택지가 아닙니다. `./editor.css`와 `./editor.js`까지 다시 쓰게 되어 앱이 아예 열리지 않습니다. 요청은 문서가 있는 디렉터리 안으로 제한됩니다. 링크는 페이지의 내용이고, 페이지의 내용은 신뢰할 수 없기 때문입니다.

## 테스트

```
swift test           81개
cd web && npm test   75개
```

Swift 쪽은 응답 정리, 엔드포인트 조립, 파일 표시 여부와 정렬, `.assets` 경로 유도, 이름 변경/새로 만들기의 이름 검증, 이미지 타입 판별과 이름 충돌, `nib-asset://`의 경로 traversal 거부, 외관 설정 왕복, 파일 간 검색을 다룹니다.

JS 쪽은 ghost text 발동 규칙(전각 문장부호와 오발동 방지 포함), 글자 수 세기(CJK는 글자 단위, 코드는 제외), 이미지 경로 재작성, 서식 문자열 변환, 아웃라인 파싱을 다룹니다.

`wordcount.js`, `format.js`, `outline.js`, `preview.js`는 CodeMirror에 의존하지 않으므로 테스트가 실제 구현을 그대로 import합니다. `ghost.js`는 CM 확장이라 그럴 수 없어서, 규칙이 일치하는지 확인하는 테스트를 하나 두어 문서와 구현이 어긋나지 않도록 합니다.

## 프로젝트

프로젝트 홈: https://github.com/howtoexitvim/Nib

## License

[MIT](LICENSE)
