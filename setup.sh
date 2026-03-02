#!/bin/bash
# =============================================================
#  JOB MATCHER APP — ONE COMMAND SETUP
#  Ubuntu 20.04 / 22.04 / 24.04
#  Usage:  bash setup.sh
# =============================================================
set -e

# ── Colors ────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; B='\033[1m'; N='\033[0m'

log()  { echo -e "${G}[✔]${N} $1"; }
warn() { echo -e "${Y}[!]${N} $1"; }
fail() { echo -e "${R}[✘]${N} $1"; exit 1; }
sec()  { echo -e "\n${C}${B}━━━━  $1  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"; }

# ── Banner ────────────────────────────────────────────────────
clear
echo -e "${C}${B}"
echo "  ╔════════════════════════════════════════════════╗"
echo "  ║     🚀  JOB MATCHER — AUTO SETUP SCRIPT        ║"
echo "  ║   Resume → AI Skills → LinkedIn/Naukri Jobs    ║"
echo "  ╚════════════════════════════════════════════════╝"
echo -e "${N}"

# ── Check OS ──────────────────────────────────────────────────
command -v apt-get &>/dev/null || fail "Requires Ubuntu/Debian (apt-get not found)"

# ── API Keys ──────────────────────────────────────────────────
sec "API KEYS"
echo ""
echo -e "${Y}You need 2 FREE API keys before we continue:${N}"
echo ""
echo -e "  ${B}1. Anthropic Claude API Key${N}  →  https://console.anthropic.com"
echo -e "     (Sign up → API Keys → Create Key)"
echo ""
echo -e "  ${B}2. RapidAPI Key (Jobs Data)${N}  →  https://rapidapi.com/letscrape-6bRBa3QguO5/api/jsearch"
echo -e "     (Sign up → Subscribe JSearch → FREE 200 req/month)"
echo ""

read -rp "$(echo -e ${C})Enter Anthropic API Key : $(echo -e ${N})" ANTHROPIC_KEY
read -rp "$(echo -e ${C})Enter RapidAPI Key      : $(echo -e ${N})" RAPIDAPI_KEY

[[ -z "$ANTHROPIC_KEY" || -z "$RAPIDAPI_KEY" ]] && fail "Both keys required."
log "API keys accepted."

# ── System packages ───────────────────────────────────────────
sec "SYSTEM UPDATE"
sudo apt-get update -qq
sudo apt-get install -y -qq curl wget git build-essential python3 python3-pip python3-venv
log "System packages ready."

# ── Node.js 20 ────────────────────────────────────────────────
sec "NODE.JS"
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x -o /tmp/nodesource_setup.sh
  sudo bash /tmp/nodesource_setup.sh
  sudo apt-get install -y -qq nodejs
fi
log "Node.js $(node --version) ready."

# ── Project folder ────────────────────────────────────────────
sec "PROJECT SETUP"
DIR="$HOME/job-matcher"
mkdir -p "$DIR"/{backend,frontend/src,frontend/public,logs,pids}
log "Project dir: $DIR"

# ── .env ──────────────────────────────────────────────────────
cat > "$DIR/backend/.env" <<EOF
ANTHROPIC_API_KEY=${ANTHROPIC_KEY}
RAPIDAPI_KEY=${RAPIDAPI_KEY}
PORT=5000
EOF
log ".env written."

# ── requirements.txt ──────────────────────────────────────────
cat > "$DIR/backend/requirements.txt" <<'EOF'
flask==3.0.0
flask-cors==4.0.0
anthropic==0.34.0
requests==2.31.0
pdfplumber==0.10.3
docx2txt==0.8
python-dotenv==1.0.0
gunicorn==21.2.0
EOF

# ── backend/app.py ────────────────────────────────────────────
cat > "$DIR/backend/app.py" <<'PYEOF'
import os, re, json, requests, pdfplumber, docx2txt
from io import BytesIO
from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv
import anthropic

load_dotenv()
app = Flask(__name__)
CORS(app)

ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY","")
RAPIDAPI_KEY      = os.environ.get("RAPIDAPI_KEY","")
claude = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY) if ANTHROPIC_API_KEY else None

SKILLS_DB = [
    "Python","Java","JavaScript","TypeScript","C++","C#","C","Go","Rust","Swift","Kotlin","PHP","Ruby","Scala","R","Bash",
    "React","Angular","Vue","Next.js","HTML","CSS","Tailwind","Bootstrap","Redux","jQuery","Svelte","SASS",
    "Node.js","Django","Flask","FastAPI","Spring Boot","Express","Laravel","ASP.NET",".NET","GraphQL","REST API","Microservices",
    "SQL","MySQL","PostgreSQL","MongoDB","Redis","SQLite","Oracle","DynamoDB","Cassandra","Elasticsearch","Firebase",
    "AWS","Azure","GCP","Docker","Kubernetes","Terraform","Ansible","Jenkins","CI/CD","GitHub Actions","DevOps","Linux",
    "Machine Learning","Deep Learning","Data Science","TensorFlow","PyTorch","Pandas","NumPy","Scikit-learn","NLP","Spark","Kafka","Airflow",
    "Power BI","Tableau","Excel","Data Analysis","Android","iOS","React Native","Flutter",
    "Git","GitHub","Jira","Figma","Agile","Scrum","Selenium","Jest","Cypress","QA","Testing",
]

def read_file(file):
    n, d = file.filename.lower(), file.read()
    try:
        if n.endswith(".pdf"):
            with pdfplumber.open(BytesIO(d)) as p:
                return "\n".join(pg.extract_text() or "" for pg in p.pages)
        elif n.endswith(".docx"): return docx2txt.process(BytesIO(d))
        elif n.endswith(".txt"):  return d.decode("utf-8","ignore")
    except: pass
    return ""

def skills_local(text):
    tl = text.lower()
    return [s for s in SKILLS_DB if re.search(r'\b'+re.escape(s.lower())+r'\b', tl)][:25]

def skills_ai(resume, manual=""):
    prompt = f"""Parse this resume and return ONLY valid JSON (no markdown):
RESUME: {resume[:4000]}
EXTRA SKILLS: {manual}

{{"skills":["sk1","sk2"],"job_titles":["Title1","Title2"],"years_experience":2,"summary":"one line"}}"""
    msg = claude.messages.create(model="claude-sonnet-4-20250514",max_tokens=800,
          messages=[{"role":"user","content":prompt}])
    raw = re.sub(r"```json|```","",msg.content[0].text.strip()).strip()
    return json.loads(raw)

def fetch_jobs(query, location, date_posted="month"):
    headers = {"x-rapidapi-key":RAPIDAPI_KEY,"x-rapidapi-host":"jsearch.p.rapidapi.com"}
    jobs = []
    for page in range(1,3):
        try:
            r = requests.get("https://jsearch.p.rapidapi.com/search",headers=headers,
                params={"query":f"{query} in {location}","page":str(page),"num_pages":"1","date_posted":date_posted},timeout=12)
            r.raise_for_status()
            for j in r.json().get("data",[]):
                desc=(j.get("job_description") or "")[:600]
                mn,mx,cur=j.get("job_min_salary"),j.get("job_max_salary"),j.get("job_salary_currency","")
                sal=f"{cur} {mn:,.0f}–{mx:,.0f}".strip() if mn and mx else (f"{cur} {mn:,.0f}+".strip() if mn else "")
                pub=(j.get("job_apply_link","") + j.get("job_publisher","")).lower()
                plat=next((p.capitalize() for p in ["linkedin","naukri","indeed","glassdoor","monster","dice"] if p in pub),"Other")
                jobs.append({"title":j.get("job_title",""),"company":j.get("employer_name",""),
                    "location":f"{j.get('job_city','')}, {j.get('job_country','')}".strip(", "),
                    "description":desc,"apply_url":j.get("job_apply_link",""),"salary":sal,
                    "job_type":j.get("job_employment_type",""),
                    "posted_date":(j.get("job_posted_at_datetime_utc") or "")[:10],
                    "platform":plat,"logo":j.get("employer_logo",""),
                    "required_skills":skills_local(desc)})
        except Exception as e: print(f"API err p{page}: {e}")
    return jobs

def score(job_sk, user_sk):
    if not job_sk: return 45
    js=[s.lower() for s in job_sk]; us=[s.lower() for s in user_sk]
    hits=sum(1 for u in us if any(u in j or j in u for j in js))
    return min(round((hits/len(js))*100,1),100)

@app.route("/health")
def health(): return jsonify({"status":"ok","claude":bool(claude),"rapidapi":bool(RAPIDAPI_KEY)})

@app.route("/search-jobs",methods=["POST"])
def search_jobs():
    try:
        resume_text=manual=""
        manual=request.form.get("manual_skills","").strip()
        location=request.form.get("location","India")
        date_posted=request.form.get("date_posted","month")

        if "resume" in request.files:
            f=request.files["resume"]
            if f and f.filename: resume_text=read_file(f)

        if not resume_text and not manual:
            return jsonify({"error":"Provide resume or skills"}),400

        extracted=[]; titles=["Software Developer"]; summary=""
        if claude and (resume_text or manual):
            try:
                ai=skills_ai(resume_text,manual)
                extracted=ai.get("skills",[]); titles=ai.get("job_titles",["Developer"]); summary=ai.get("summary","")
            except Exception as e:
                print(f"Claude fallback: {e}")
                extracted=skills_local(resume_text+" "+manual)
        else:
            extracted=skills_local(resume_text+" "+manual)
            if manual: extracted=list(dict.fromkeys([s.strip() for s in manual.split(",") if s.strip()]+extracted))

        if not extracted: extracted=[manual] if manual else ["developer"]
        primary=extracted[0]
        queries=list(dict.fromkeys([f"{titles[0]} {primary}",titles[0],primary]))

        all_jobs,seen=[],set()
        for q in queries[:2]:
            for j in fetch_jobs(q,location,date_posted):
                k=(j["title"].lower(),j["company"].lower())
                if k not in seen:
                    seen.add(k); j["match_score"]=score(j["required_skills"],extracted); all_jobs.append(j)

        all_jobs.sort(key=lambda x:x.get("match_score",0),reverse=True)
        return jsonify({"extracted_skills":extracted,"job_titles":titles,"summary":summary,"total":len(all_jobs),"jobs":all_jobs[:40]})
    except Exception as e:
        print(f"Error: {e}"); return jsonify({"error":str(e)}),500

if __name__=="__main__":
    port=int(os.environ.get("PORT",5000))
    print(f"\n🚀 API → http://localhost:{port}")
    print(f"   Claude: {'✅' if claude else '⚠️  local fallback'}  |  RapidAPI: {'✅' if RAPIDAPI_KEY else '❌'}\n")
    app.run(host="0.0.0.0",port=port,debug=False)
PYEOF
log "backend/app.py written."

# ── Python venv + packages ────────────────────────────────────
sec "PYTHON PACKAGES"
cd "$DIR/backend"
python3 -m venv venv
source venv/bin/activate
pip install -q --upgrade pip
pip install -q -r requirements.txt
deactivate
log "Python packages installed."

# ── Frontend files ────────────────────────────────────────────
sec "FRONTEND FILES"

cat > "$DIR/frontend/package.json" <<'EOF'
{
  "name": "job-matcher-frontend",
  "private": true,
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite --host 0.0.0.0 --port 3000",
    "build": "vite build",
    "preview": "vite preview --host 0.0.0.0 --port 3000"
  },
  "dependencies": { "react": "^18.2.0", "react-dom": "^18.2.0" },
  "devDependencies": { "@vitejs/plugin-react": "^4.2.0", "vite": "^5.1.0" }
}
EOF

cat > "$DIR/frontend/vite.config.js" <<'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0', port: 3000,
    proxy: { '/api': { target: 'http://localhost:5000', changeOrigin: true, rewrite: p => p.replace(/^\/api/,'') } }
  }
})
EOF

cat > "$DIR/frontend/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/>
<title>Job Matcher — AI Resume Analyzer</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>💼</text></svg>"/>
</head><body><div id="root"></div><script type="module" src="/src/main.jsx"></script></body></html>
EOF

cat > "$DIR/frontend/src/main.jsx" <<'EOF'
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'
ReactDOM.createRoot(document.getElementById('root')).render(<React.StrictMode><App/></React.StrictMode>)
EOF

# Copy full App.jsx (written separately by setup)
cp /tmp/App.jsx "$DIR/frontend/src/App.jsx" 2>/dev/null || warn "App.jsx will need to be placed manually (see github)"

# ── npm install ───────────────────────────────────────────────
cd "$DIR/frontend"
npm install --silent
log "Frontend packages installed."

# ── start / stop / status scripts ─────────────────────────────
sec "MANAGEMENT SCRIPTS"

cat > "$DIR/start.sh" <<EOF
#!/bin/bash
echo ""
echo "🚀 Starting Job Matcher..."
mkdir -p ~/job-matcher/{logs,pids}

# Backend
cd ~/job-matcher/backend
source venv/bin/activate
nohup python app.py > ~/job-matcher/logs/backend.log 2>&1 &
echo \$! > ~/job-matcher/pids/backend.pid
deactivate
echo "  ✅ Backend  → http://localhost:5000"
sleep 2

# Frontend
cd ~/job-matcher/frontend
nohup npm run dev > ~/job-matcher/logs/frontend.log 2>&1 &
echo \$! > ~/job-matcher/pids/frontend.pid
echo "  ✅ Frontend → http://localhost:3000"

echo ""
echo "  🌐 Open: http://localhost:3000"
echo "  📋 Logs: tail -f ~/job-matcher/logs/backend.log"
echo "  🛑 Stop: bash ~/job-matcher/stop.sh"
echo ""
EOF

cat > "$DIR/stop.sh" <<'EOF'
#!/bin/bash
echo "🛑 Stopping Job Matcher..."
[ -f ~/job-matcher/pids/backend.pid ]  && kill $(cat ~/job-matcher/pids/backend.pid)  2>/dev/null && echo "  ✅ Backend stopped"
[ -f ~/job-matcher/pids/frontend.pid ] && kill $(cat ~/job-matcher/pids/frontend.pid) 2>/dev/null && echo "  ✅ Frontend stopped"
pkill -f "app.py" 2>/dev/null; pkill -f "vite" 2>/dev/null
echo "Done."
EOF

cat > "$DIR/status.sh" <<'EOF'
#!/bin/bash
echo "📊 Job Matcher Status:"
curl -s http://localhost:5000/health > /dev/null 2>&1 \
  && echo "  ✅ Backend  → http://localhost:5000 (RUNNING)" \
  || echo "  ❌ Backend  → NOT running"
curl -s http://localhost:3000 > /dev/null 2>&1 \
  && echo "  ✅ Frontend → http://localhost:3000 (RUNNING)" \
  || echo "  ❌ Frontend → NOT running"
EOF

chmod +x "$DIR/start.sh" "$DIR/stop.sh" "$DIR/status.sh"
log "start.sh / stop.sh / status.sh ready."

# ── systemd (auto-start on reboot) ────────────────────────────
sec "SYSTEMD (auto-start on reboot)"
sudo bash -c "cat > /etc/systemd/system/job-matcher-backend.service" <<SVCEOF
[Unit]
Description=Job Matcher Backend
After=network.target
[Service]
Type=simple
User=$USER
WorkingDirectory=$DIR/backend
ExecStart=$DIR/backend/venv/bin/python app.py
EnvironmentFile=$DIR/backend/.env
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
SVCEOF

sudo bash -c "cat > /etc/systemd/system/job-matcher-frontend.service" <<SVCEOF
[Unit]
Description=Job Matcher Frontend
After=network.target
[Service]
Type=simple
User=$USER
WorkingDirectory=$DIR/frontend
ExecStart=/usr/bin/npm run dev
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
SVCEOF

sudo systemctl daemon-reload
sudo systemctl enable job-matcher-backend job-matcher-frontend 2>/dev/null && log "Systemd auto-start enabled." || warn "Systemd enable skipped (non-fatal)"

# ── DONE ──────────────────────────────────────────────────────
echo ""
echo -e "${G}${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${G}${B}  ✅  SETUP COMPLETE!${N}"
echo -e "${G}${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""
echo -e "  Project : ${C}$DIR${N}"
echo ""
echo -e "  ${B}Start  :${N} ${C}bash ~/job-matcher/start.sh${N}"
echo -e "  ${B}Stop   :${N} ${C}bash ~/job-matcher/stop.sh${N}"
echo -e "  ${B}Status :${N} ${C}bash ~/job-matcher/status.sh${N}"
echo -e "  ${B}Logs   :${N} ${C}tail -f ~/job-matcher/logs/backend.log${N}"
echo ""
echo -e "${Y}Start the app now? (y/n)${N}"
read -rp "→ " GO
[[ "$GO" == "y" || "$GO" == "Y" ]] && bash "$DIR/start.sh"
