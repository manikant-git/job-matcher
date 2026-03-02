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
cat > "$DIR/frontend/src/App.jsx" << 'APPEOF'
import { useState, useCallback } from "react";
const API = "/api";
const injectStyles = () => {
  if (document.getElementById("jm-styles")) return;
  const s = document.createElement("style");
  s.id = "jm-styles";
  s.textContent = `
@import url('https://fonts.googleapis.com/css2?family=Syne:wght@400;600;700;800&family=Outfit:wght@300;400;500;600&display=swap');
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{--bg:#080810;--surf:#0f0f1a;--card:#141422;--bdr:#22223a;--acc:#6366f1;--acc2:#f472b6;--acc3:#34d399;--txt:#ededf5;--muted:#6b6b8f;--shadow:0 20px 60px rgba(0,0,0,.5)}
html{scroll-behavior:smooth}
body{background:var(--bg);background-image:radial-gradient(ellipse 80% 50% at 20% -10%,rgba(99,102,241,.12) 0%,transparent 60%),radial-gradient(ellipse 60% 40% at 80% 100%,rgba(244,114,182,.08) 0%,transparent 60%);color:var(--txt);font-family:'Outfit',sans-serif;min-height:100vh}
::-webkit-scrollbar{width:6px}::-webkit-scrollbar-track{background:var(--bg)}::-webkit-scrollbar-thumb{background:var(--bdr);border-radius:3px}
@keyframes fadeUp{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:translateY(0)}}
@keyframes spin{to{transform:rotate(360deg)}}
@keyframes shimmer{0%{background-position:-200% 0}100%{background-position:200% 0}}
.fade-up{animation:fadeUp .5s ease both}.fa-1{animation-delay:.1s}.fa-2{animation-delay:.2s}.fa-3{animation-delay:.3s}
.app{max-width:1080px;margin:0 auto;padding:48px 20px 80px}
.hdr{text-align:center;margin-bottom:56px}
.chip{display:inline-flex;align-items:center;gap:6px;background:rgba(99,102,241,.12);border:1px solid rgba(99,102,241,.3);color:#a5b4fc;padding:5px 16px;border-radius:20px;font-size:.72rem;font-weight:600;letter-spacing:.1em;text-transform:uppercase;margin-bottom:20px}
.hdr h1{font-family:'Syne',sans-serif;font-size:clamp(2.2rem,5vw,4rem);font-weight:800;line-height:1.05;background:linear-gradient(135deg,#818cf8 0%,#f472b6 45%,#34d399 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.hdr p{color:var(--muted);margin-top:14px;font-size:1.05rem;font-weight:300;max-width:520px;margin-inline:auto}
.steps{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:12px;margin-bottom:40px}
.step{background:var(--surf);border:1px solid var(--bdr);border-radius:16px;padding:20px}
.step-n{font-family:'Syne',sans-serif;font-size:2rem;font-weight:800;color:rgba(99,102,241,.22);line-height:1;margin-bottom:8px}
.step h4{font-family:'Syne',sans-serif;font-size:.88rem;font-weight:700;margin-bottom:4px}
.step p{color:var(--muted);font-size:.8rem;line-height:1.5}
.panel{background:var(--surf);border:1px solid var(--bdr);border-radius:22px;padding:32px;margin-bottom:16px}
.sec-lbl{font-family:'Syne',sans-serif;font-size:.72rem;font-weight:700;text-transform:uppercase;letter-spacing:.12em;color:var(--muted);margin-bottom:12px}
.upload{border:2px dashed var(--bdr);border-radius:18px;padding:44px 24px;text-align:center;cursor:pointer;transition:all .3s;position:relative}
.upload.drag,.upload:hover{border-color:var(--acc);background:rgba(99,102,241,.06)}
.upload input{position:absolute;inset:0;opacity:0;cursor:pointer;width:100%;height:100%}
.upload h3{font-family:'Syne',sans-serif;font-size:1.15rem;font-weight:700;margin-bottom:6px}
.upload p{color:var(--muted);font-size:.88rem}
.fname{margin-top:14px;color:var(--acc3);font-weight:600;font-size:.9rem}
.divider{display:flex;align-items:center;gap:16px;margin:28px 0;color:var(--muted);font-size:.82rem}
.divider::before,.divider::after{content:'';flex:1;border-top:1px solid var(--bdr)}
.textarea{width:100%;background:#141422;border:1px solid var(--bdr);border-radius:14px;padding:14px 18px;color:var(--txt);font-family:'Outfit',sans-serif;font-size:.95rem;outline:none;resize:vertical;min-height:80px;transition:border-color .2s}
.textarea:focus{border-color:var(--acc)}.textarea::placeholder{color:var(--muted)}
.row2{display:grid;grid-template-columns:1fr 1fr 1fr;gap:14px;margin-top:20px}
@media(max-width:640px){.row2{grid-template-columns:1fr}}
.sel{background:#141422;border:1px solid var(--bdr);border-radius:14px;padding:12px 16px;color:var(--txt);font-family:'Outfit',sans-serif;font-size:.92rem;outline:none;width:100%;cursor:pointer;transition:border-color .2s}
.sel:focus{border-color:var(--acc)}
.btn{background:linear-gradient(135deg,#6366f1,#8b5cf6);color:#fff;border:none;border-radius:16px;padding:16px 32px;font-family:'Syne',sans-serif;font-weight:700;font-size:1rem;cursor:pointer;width:100%;margin-top:24px;transition:all .3s;letter-spacing:.03em;position:relative;overflow:hidden}
.btn::after{content:'';position:absolute;inset:0;background:linear-gradient(90deg,transparent,rgba(255,255,255,.08),transparent);background-size:200% 100%;animation:shimmer 2s infinite}
.btn:hover:not(:disabled){transform:translateY(-2px);box-shadow:0 16px 48px rgba(99,102,241,.45)}
.btn:disabled{opacity:.45;cursor:not-allowed}
.spinner{display:inline-block;width:16px;height:16px;border:2px solid rgba(255,255,255,.3);border-top-color:#fff;border-radius:50%;animation:spin .8s linear infinite;vertical-align:middle;margin-right:8px}
.err-box{background:rgba(244,114,182,.07);border:1px solid rgba(244,114,182,.28);border-radius:14px;padding:14px 18px;color:#f9a8d4;font-size:.9rem;margin-top:16px}
.skills-panel{background:var(--card);border:1px solid var(--bdr);border-radius:18px;padding:22px 26px;margin:36px 0 28px}
.skills-panel h3{font-family:'Syne',sans-serif;font-size:.75rem;text-transform:uppercase;letter-spacing:.12em;color:var(--muted);margin-bottom:14px}
.tags{display:flex;flex-wrap:wrap;gap:8px}
.tag{background:rgba(99,102,241,.12);border:1px solid rgba(99,102,241,.25);color:#a5b4fc;padding:4px 13px;border-radius:20px;font-size:.8rem;font-weight:500}
.res-bar{display:flex;align-items:center;justify-content:space-between;margin:0 0 22px}
.res-bar h2{font-family:'Syne',sans-serif;font-size:1.6rem;font-weight:800}
.cnt-badge{background:var(--acc);color:#fff;padding:4px 14px;border-radius:20px;font-size:.82rem;font-weight:700}
.jgrid{display:grid;gap:14px}
.jcard{background:var(--card);border:1px solid var(--bdr);border-radius:20px;padding:24px;transition:all .3s;position:relative;overflow:hidden}
.jcard::before{content:'';position:absolute;top:0;left:0;right:0;height:2px;background:linear-gradient(90deg,var(--acc),var(--acc2),var(--acc3));opacity:0;transition:opacity .3s}
.jcard:hover{border-color:rgba(99,102,241,.35);transform:translateY(-3px);box-shadow:var(--shadow)}
.jcard:hover::before{opacity:1}
.jtop{display:flex;justify-content:space-between;align-items:flex-start;gap:12px;margin-bottom:10px}
.jleft{flex:1;min-width:0}.jright{display:flex;flex-direction:column;align-items:flex-end;gap:6px;flex-shrink:0}
.jt{font-family:'Syne',sans-serif;font-size:1.05rem;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.jco{color:var(--acc);font-weight:500;font-size:.92rem;margin-top:3px}
.jlogo{width:32px;height:32px;border-radius:8px;object-fit:contain;background:#1a1a2e;border:1px solid var(--bdr);padding:2px;margin-bottom:6px}
.score{padding:4px 12px;border-radius:20px;font-size:.78rem;font-weight:700;white-space:nowrap}
.score.hi{background:rgba(52,211,153,.12);border:1px solid rgba(52,211,153,.3);color:#34d399}
.score.md{background:rgba(251,191,36,.1);border:1px solid rgba(251,191,36,.3);color:#fbbf24}
.score.lo{background:rgba(244,114,182,.1);border:1px solid rgba(244,114,182,.3);color:#f472b6}
.plat{display:inline-flex;align-items:center;gap:4px;padding:3px 10px;border-radius:8px;font-size:.72rem;font-weight:700}
.pl-linkedin{background:rgba(10,102,194,.15);color:#60a5fa;border:1px solid rgba(10,102,194,.3)}
.pl-naukri{background:rgba(255,87,34,.12);color:#fb923c;border:1px solid rgba(255,87,34,.3)}
.pl-indeed{background:rgba(0,114,232,.12);color:#60a5fa;border:1px solid rgba(0,114,232,.3)}
.pl-glassdoor{background:rgba(15,157,88,.12);color:#4ade80;border:1px solid rgba(15,157,88,.3)}
.pl-other{background:rgba(255,255,255,.06);color:var(--muted);border:1px solid var(--bdr)}
.jmeta{display:flex;flex-wrap:wrap;gap:10px;margin:10px 0 12px}
.mi{display:flex;align-items:center;gap:4px;color:var(--muted);font-size:.82rem}
.jdesc{color:var(--muted);font-size:.86rem;line-height:1.65;margin-bottom:14px;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
.jskills{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:16px}
.jsk{background:rgba(255,255,255,.04);border:1px solid var(--bdr);color:var(--muted);padding:3px 10px;border-radius:10px;font-size:.76rem}
.jsk.m{background:rgba(99,102,241,.1);border-color:rgba(99,102,241,.3);color:#a5b4fc}
.apply-btn{display:inline-flex;align-items:center;gap:6px;background:transparent;border:1px solid var(--acc);color:var(--acc);padding:8px 20px;border-radius:10px;font-size:.86rem;font-weight:600;cursor:pointer;transition:all .22s;text-decoration:none}
.apply-btn:hover{background:var(--acc);color:#fff}
.empty{text-align:center;padding:64px 24px}
.empty .ico{font-size:3.5rem;opacity:.3;margin-bottom:16px}
.empty h3{font-family:'Syne',sans-serif;font-size:1.25rem;color:var(--txt);margin-bottom:8px}
.empty p{color:var(--muted);font-size:.9rem}
`;
  document.head.appendChild(s);
};
const PLAT_MAP={linkedin:{cls:"pl-linkedin",ico:"💼"},naukri:{cls:"pl-naukri",ico:"🔷"},indeed:{cls:"pl-indeed",ico:"🔵"},glassdoor:{cls:"pl-glassdoor",ico:"🟢"}};
const getPlatInfo=(p="")=>PLAT_MAP[p.toLowerCase()]||{cls:"pl-other",ico:"🌐"};
const getScoreCls=s=>s>=70?"hi":s>=40?"md":"lo";
function JobCard({job,userSkills}){
  const matched=(job.required_skills||[]).filter(sk=>(userSkills||[]).some(us=>us.toLowerCase().includes(sk.toLowerCase())||sk.toLowerCase().includes(us.toLowerCase())));
  const sc=job.match_score||0;
  const{cls,ico}=getPlatInfo(job.platform);
  return(
    <div className="jcard fade-up">
      <div className="jtop">
        <div className="jleft">
          {job.logo&&<img src={job.logo} alt="" className="jlogo" onError={e=>e.target.style.display="none"}/>}
          <div className="jt">{job.title}</div>
          <div className="jco">{job.company}</div>
        </div>
        <div className="jright">
          <span className={`score ${getScoreCls(sc)}`}>{sc?`${Math.round(sc)}% Match`:"New"}</span>
          <span className={`plat ${cls}`}>{ico} {job.platform||"Jobs"}</span>
        </div>
      </div>
      <div className="jmeta">
        {job.location&&<span className="mi">📍 {job.location}</span>}
        {job.salary&&<span className="mi">💰 {job.salary}</span>}
        {job.job_type&&<span className="mi">⏱ {job.job_type}</span>}
        {job.posted_date&&<span className="mi">🕐 {job.posted_date}</span>}
      </div>
      {job.description&&<p className="jdesc">{job.description}</p>}
      {(job.required_skills||[]).length>0&&(
        <div className="jskills">
          {job.required_skills.map((sk,i)=>(
            <span key={i} className={`jsk${matched.includes(sk)?" m":""}`}>{matched.includes(sk)?"✓ ":""}{sk}</span>
          ))}
        </div>
      )}
      {job.apply_url&&<a href={job.apply_url} target="_blank" rel="noopener noreferrer" className="apply-btn">Apply Now →</a>}
    </div>
  );
}
export default function App(){
  injectStyles();
  const[file,setFile]=useState(null);
  const[skills,setSkills]=useState("");
  const[location,setLocation]=useState("India");
  const[expLevel,setExpLevel]=useState("any");
  const[dateFilt,setDateFilt]=useState("month");
  const[loading,setLoading]=useState(false);
  const[results,setResults]=useState(null);
  const[error,setError]=useState(null);
  const[drag,setDrag]=useState(false);
  const handleFile=useCallback(f=>{
    if(!f)return;
    const ok=f.name.endsWith(".pdf")||f.name.endsWith(".docx")||f.name.endsWith(".txt");
    if(ok){setFile(f);setError(null);}else setError("Only PDF, DOCX or TXT files are supported.");
  },[]);
  const search=async()=>{
    if(!file&&!skills.trim()){setError("Please upload your resume OR enter your skills.");return;}
    setLoading(true);setError(null);setResults(null);
    try{
      const fd=new FormData();
      if(file)fd.append("resume",file);
      fd.append("manual_skills",skills);fd.append("location",location);
      fd.append("experience",expLevel);fd.append("date_posted",dateFilt);
      const res=await fetch(`${API}/search-jobs`,{method:"POST",body:fd});
      const data=await res.json();
      if(!res.ok)throw new Error(data.error||"Server error");
      setResults(data);
    }catch(e){
      setError(`${e.message}. Make sure backend is running: bash ~/job-matcher/start.sh`);
    }finally{setLoading(false);}
  };
  return(
    <div className="app">
      <header className="hdr fade-up">
        <div className="chip">✨ AI-Powered Job Matcher</div>
        <h1>Find Your Dream Job</h1>
        <p>Upload your resume → AI extracts your skills → Matches jobs from LinkedIn, Naukri, Indeed and more</p>
      </header>
      <div className="steps">
        {[["01","Upload Resume","PDF, DOCX or TXT"],["02","AI Analyzes","Claude extracts your skills"],["03","Jobs Fetched","LinkedIn · Naukri · Indeed"],["04","Ranked Results","Best matches shown first"]].map(([n,t,d],i)=>(
          <div key={n} className={`step fade-up fa-${i+1}`}><div className="step-n">{n}</div><h4>{t}</h4><p>{d}</p></div>
        ))}
      </div>
      <div className="panel fade-up">
        <div className="sec-lbl">📄 Upload Resume</div>
        <div className={`upload${drag?" drag":""}`}
          onDragOver={e=>{e.preventDefault();setDrag(true)}}
          onDragLeave={()=>setDrag(false)}
          onDrop={e=>{e.preventDefault();setDrag(false);handleFile(e.dataTransfer.files[0])}}>
          <input type="file" accept=".pdf,.docx,.txt" onChange={e=>handleFile(e.target.files[0])}/>
          <div style={{fontSize:"2.8rem",marginBottom:14}}>📄</div>
          <h3>Drop your resume here</h3>
          <p>Supports PDF, DOCX, TXT · Click to browse</p>
          {file&&<div className="fname">✅ {file.name}</div>}
        </div>
        <div className="divider">OR</div>
        <div className="sec-lbl">⌨️ Enter Skills Manually</div>
        <textarea className="textarea" placeholder="e.g. Python, React, Node.js, SQL, AWS, 3 years experience..." value={skills} onChange={e=>setSkills(e.target.value)}/>
        <div className="row2">
          <div>
            <div className="sec-lbl">📍 Location</div>
            <select className="sel" value={location} onChange={e=>setLocation(e.target.value)}>
              {["India","Hyderabad","Bangalore","Mumbai","Delhi","Chennai","Pune","Kolkata","Noida","Gurgaon","Remote","USA","UK","Canada","Australia"].map(c=><option key={c}>{c}</option>)}
            </select>
          </div>
          <div>
            <div className="sec-lbl">🏆 Experience</div>
            <select className="sel" value={expLevel} onChange={e=>setExpLevel(e.target.value)}>
              <option value="any">Any Level</option>
              <option value="fresher">Fresher (0-1 yr)</option>
              <option value="junior">Junior (1-3 yrs)</option>
              <option value="mid">Mid (3-5 yrs)</option>
              <option value="senior">Senior (5+ yrs)</option>
            </select>
          </div>
          <div>
            <div className="sec-lbl">🕐 Date Posted</div>
            <select className="sel" value={dateFilt} onChange={e=>setDateFilt(e.target.value)}>
              <option value="today">Today</option>
              <option value="3days">Last 3 Days</option>
              <option value="week">This Week</option>
              <option value="month">This Month</option>
              <option value="all">All Time</option>
            </select>
          </div>
        </div>
        {error&&<div className="err-box">⚠️ {error}</div>}
        <button className="btn" onClick={search} disabled={loading}>
          {loading?<><span className="spinner"/>Searching Jobs...</>:"🚀 Find Matching Jobs"}
        </button>
      </div>
      {results&&(
        <>
          {results.extracted_skills?.length>0&&(
            <div className="skills-panel fade-up">
              <h3>🧠 Skills Extracted from Your Resume</h3>
              <div className="tags">{results.extracted_skills.map((sk,i)=><span key={i} className="tag">{sk}</span>)}</div>
            </div>
          )}
          <div className="res-bar">
            <h2>Matched Jobs</h2>
            <span className="cnt-badge">{results.jobs?.length||0} found</span>
          </div>
          {results.jobs?.length>0?(
            <div className="jgrid">{results.jobs.map((j,i)=><JobCard key={i} job={j} userSkills={results.extracted_skills||[]}/>)}</div>
          ):(
            <div className="empty"><div className="ico">🔍</div><h3>No jobs found</h3><p>Try different skills or "All Time" date filter</p></div>
          )}
        </>
      )}
    </div>
  );
}
APPEOF
log "frontend/src/App.jsx written."

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

