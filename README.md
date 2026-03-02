# 💼 Job Matcher — AI Resume Analyzer

> Upload your resume → Claude AI extracts your skills → Finds matching jobs from LinkedIn, Naukri, Indeed, Glassdoor

## ⚡ One Command Setup (Ubuntu)

```bash
git clone https://github.com/YOUR_USERNAME/job-matcher.git
cd job-matcher
bash setup.sh
```

The script will ask for your 2 free API keys, then set everything up automatically.

## 🔑 Get Free API Keys

| Key | Where | Cost |
|-----|-------|------|
| Anthropic Claude | https://console.anthropic.com | Free $5 credits |
| RapidAPI (JSearch) | https://rapidapi.com/letscrape-6bRBa3QguO5/api/jsearch | Free 200 req/month |

## 🚀 Usage

```bash
bash ~/job-matcher/start.sh    # Start both backend + frontend
bash ~/job-matcher/stop.sh     # Stop
bash ~/job-matcher/status.sh   # Check status
```

Open **http://localhost:3000** in your browser.

## 🏗 Tech Stack

- **Frontend**: React + Vite
- **Backend**: Python Flask
- **AI**: Claude claude-sonnet-4 (skill extraction)
- **Jobs API**: JSearch via RapidAPI (LinkedIn, Naukri, Indeed, Glassdoor)

## 📁 Structure

```
job-matcher/
├── setup.sh              ← Run this once to install everything
├── start.sh              ← Start app
├── stop.sh               ← Stop app
├── backend/
│   ├── app.py            ← Flask API
│   ├── requirements.txt
│   └── .env              ← Your API keys (created by setup.sh)
└── frontend/
    ├── src/App.jsx       ← React UI
    ├── vite.config.js
    └── package.json
```
# job-matcher
