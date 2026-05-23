# TikDown
**No-watermark TikTok video downloader for iPhone**  
Developer: KhinPhunnadet | Built 100% via GitHub Actions

---

## Repo Structure
```
TikDown/
├── Sources/
│   ├── TikDown.swift       ← All app code (Model + ViewModel + Views)
│   └── Info.plist          ← Permissions
├── project.yml             ← XcodeGen config (no .xcodeproj needed!)
├── .github/
│   └── workflows/
│       └── build.yml       ← GitHub Actions build
└── README.md
```

## How to Build (No Mac Needed)

### Step 1 — Push to GitHub
```bash
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/thenullastris/TikDown.git
git push -u origin main
```

### Step 2 — Run the Action
1. Go to your repo → **Actions** tab
2. Select **Build TikDown IPA** → **Run workflow**
3. Wait ~5 min → download IPA from **Artifacts**

### Step 3 — Install on iPhone

| Method | Needs | Permanent? |
|---|---|---|
| **TrollStore** | Just your iPhone | ✅ Yes |
| **Sideloadly** | PC/Mac once | ❌ 7 days |
| **AltStore** | AltServer | ❌ 7 days |

TrollStore is best — AirDrop IPA → open with TrollStore → done.

---

## API: tikwm.com (free, no key)
```
GET https://www.tikwm.com/api/?url=<tiktok_url>
```
- `data.play` → watermark-free MP4
- `data.wmplay` → with watermark MP4

---

## Roadmap
- [ ] Share Extension (share from TikTok app directly)
- [ ] iOS 26 Liquid Glass UI
- [ ] Download history
- [ ] Audio-only extraction
