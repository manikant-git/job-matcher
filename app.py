"""
Job Matcher Backend - Flask API
Extracts skills from resume using Claude AI + fetches jobs via JSearch (RapidAPI)
"""

import os
import re
import json
import requests
import pdfplumber
import docx2txt
from io import BytesIO
from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv
import anthropic

load_dotenv()

app = Flask(__name__)
CORS(app)

ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
RAPIDAPI_KEY      = os.environ.get("RAPIDAPI_KEY", "")

claude = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY) if ANTHROPIC_API_KEY else None

# ─── Skill Database (free fallback, no API needed) ──────────────────────────
SKILLS_DB = [
    # Programming Languages
    "Python","Java","JavaScript","TypeScript","C++","C#","C","Go","Rust","Swift",
    "Kotlin","PHP","Ruby","Scala","R","MATLAB","Perl","Bash","Shell","PowerShell",
    # Frontend
    "React","Angular","Vue","Next.js","Nuxt","HTML","CSS","Tailwind","Bootstrap",
    "Redux","jQuery","Webpack","Vite","Svelte","SASS","LESS",
    # Backend
    "Node.js","Django","Flask","FastAPI","Spring Boot","Express","Laravel","Rails",
    "ASP.NET",".NET","Hibernate","GraphQL","REST API","gRPC","Microservices",
    # Databases
    "SQL","MySQL","PostgreSQL","MongoDB","Redis","SQLite","Oracle","SQL Server",
    "DynamoDB","Cassandra","Elasticsearch","Firebase","Supabase","Neo4j",
    # Cloud & DevOps
    "AWS","Azure","GCP","Docker","Kubernetes","Terraform","Ansible","Jenkins",
    "CI/CD","GitHub Actions","GitLab CI","Nginx","Linux","Ubuntu","DevOps",
    "Helm","Prometheus","Grafana","EKS","ECS","Lambda","S3","EC2","RDS",
    # Data & AI/ML
    "Machine Learning","Deep Learning","Data Science","TensorFlow","PyTorch",
    "Keras","Pandas","NumPy","Scikit-learn","OpenCV","NLP","LLM","Spark",
    "Hadoop","Kafka","Airflow","Power BI","Tableau","Excel","Data Analysis",
    # Mobile
    "Android","iOS","React Native","Flutter","Xamarin","Swift UI","Jetpack Compose",
    # Tools & Other
    "Git","GitHub","GitLab","Jira","Confluence","Figma","Postman","Swagger",
    "Agile","Scrum","Kanban","REST","JSON","XML","YAML","Linux","Vim","VSCode",
    # Business/Domain
    "SEO","Digital Marketing","Project Management","Product Management",
    "Business Analysis","QA","Testing","Selenium","Jest","Cypress","JUnit",
]

def extract_text_from_file(file):
    """Read text from uploaded PDF / DOCX / TXT."""
    name = file.filename.lower()
    data = file.read()
    try:
        if name.endswith(".pdf"):
            with pdfplumber.open(BytesIO(data)) as pdf:
                return "\n".join(p.extract_text() or "" for p in pdf.pages)
        elif name.endswith(".docx"):
            return docx2txt.process(BytesIO(data))
        elif name.endswith(".txt"):
            return data.decode("utf-8", errors="ignore")
    except Exception as e:
        print(f"File read error: {e}")
    return ""


def extract_skills_local(text):
    """Free local skill extraction — no API needed."""
    text_lower = text.lower()
    found = []
    for skill in SKILLS_DB:
        # Match whole word (avoid "C" matching "science" etc.)
        pattern = r'\b' + re.escape(skill.lower()) + r'\b'
        if re.search(pattern, text_lower):
            found.append(skill)
    return found[:25]


def extract_skills_ai(resume_text, manual_skills=""):
    """Use Claude to extract skills + suggest job titles (better accuracy)."""
    prompt = f"""You are a professional resume parser. Extract structured info from this resume.

RESUME:
{resume_text[:4000]}

EXTRA SKILLS FROM USER: {manual_skills}

Respond ONLY with valid JSON (no markdown, no explanation):
{{
  "skills": ["skill1", "skill2"],
  "job_titles": ["Best Job Title 1", "Best Job Title 2"],
  "years_experience": 3,
  "level": "mid",
  "summary": "one line summary"
}}"""

    msg = claude.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=800,
        messages=[{"role": "user", "content": prompt}]
    )
    raw = msg.content[0].text.strip()
    raw = re.sub(r"```json|```", "", raw).strip()
    return json.loads(raw)


def fetch_jobs(query, location, date_posted="month"):
    """Fetch jobs from JSearch RapidAPI (covers LinkedIn, Indeed, Glassdoor, Naukri)."""
    url = "https://jsearch.p.rapidapi.com/search"
    headers = {
        "x-rapidapi-key":  RAPIDAPI_KEY,
        "x-rapidapi-host": "jsearch.p.rapidapi.com"
    }
    jobs = []
    for page in range(1, 3):
        try:
            params = {
                "query":      f"{query} in {location}",
                "page":       str(page),
                "num_pages":  "1",
                "date_posted": date_posted,
            }
            r = requests.get(url, headers=headers, params=params, timeout=12)
            r.raise_for_status()
            for j in r.json().get("data", []):
                desc = (j.get("job_description") or "")[:600]
                jobs.append({
                    "title":          j.get("job_title", ""),
                    "company":        j.get("employer_name", ""),
                    "location":       f"{j.get('job_city','')}, {j.get('job_country','')}".strip(", "),
                    "description":    desc,
                    "apply_url":      j.get("job_apply_link", ""),
                    "salary":         _salary(j),
                    "job_type":       j.get("job_employment_type", ""),
                    "posted_date":    (j.get("job_posted_at_datetime_utc") or "")[:10],
                    "platform":       _platform(j.get("job_apply_link",""), j.get("job_publisher","")),
                    "required_skills": extract_skills_local(desc),
                    "logo":           j.get("employer_logo", ""),
                })
        except Exception as e:
            print(f"JSearch error page {page}: {e}")
    return jobs


def _salary(j):
    mn, mx, cur = j.get("job_min_salary"), j.get("job_max_salary"), j.get("job_salary_currency","")
    if mn and mx:  return f"{cur} {mn:,.0f} – {mx:,.0f}".strip()
    if mn:         return f"{cur} {mn:,.0f}+".strip()
    return ""


def _platform(url, publisher):
    s = (url + publisher).lower()
    for p in ["linkedin","naukri","indeed","glassdoor","monster","shine","ziprecruiter","dice"]:
        if p in s: return p.capitalize()
    return publisher.capitalize() if publisher else "Other"


def match_score(job_skills, user_skills):
    if not job_skills: return 45
    js = [s.lower() for s in job_skills]
    us = [s.lower() for s in user_skills]
    hits = sum(1 for u in us if any(u in j or j in u for j in js))
    return min(round((hits / len(js)) * 100, 1), 100)


# ─── Routes ─────────────────────────────────────────────────────────────────

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "claude": bool(claude), "rapidapi": bool(RAPIDAPI_KEY)})


@app.route("/search-jobs", methods=["POST"])
def search_jobs():
    try:
        resume_text   = ""
        manual_skills = request.form.get("manual_skills", "").strip()
        location      = request.form.get("location", "India")
        date_filter   = request.form.get("date_posted", "month")

        # 1. Extract resume text
        if "resume" in request.files:
            f = request.files["resume"]
            if f and f.filename:
                resume_text = extract_text_from_file(f)

        if not resume_text and not manual_skills:
            return jsonify({"error": "Please upload a resume or enter skills."}), 400

        # 2. Extract skills (AI if available, else local)
        extracted_skills = []
        job_titles       = ["Software Developer"]
        summary          = ""

        if claude and (resume_text or manual_skills):
            try:
                ai = extract_skills_ai(resume_text, manual_skills)
                extracted_skills = ai.get("skills", [])
                job_titles       = ai.get("job_titles", ["Software Developer"])
                summary          = ai.get("summary", "")
            except Exception as e:
                print(f"Claude AI fallback: {e}")
                extracted_skills = extract_skills_local(resume_text + " " + manual_skills)
        else:
            extracted_skills = extract_skills_local(resume_text + " " + manual_skills)
            if manual_skills:
                manual_list = [s.strip() for s in manual_skills.split(",") if s.strip()]
                extracted_skills = list(dict.fromkeys(manual_list + extracted_skills))

        if not extracted_skills:
            extracted_skills = [manual_skills] if manual_skills else ["developer"]

        # 3. Build search queries
        primary = extracted_skills[0] if extracted_skills else "developer"
        queries = list(dict.fromkeys([
            f"{job_titles[0]} {primary}",
            job_titles[0],
            f"{primary} developer" if "develop" not in primary.lower() else primary,
        ]))

        # 4. Fetch & deduplicate jobs
        all_jobs, seen = [], set()
        for q in queries[:2]:
            for job in fetch_jobs(q, location, date_filter):
                key = (job["title"].lower(), job["company"].lower())
                if key not in seen:
                    seen.add(key)
                    job["match_score"] = match_score(job["required_skills"], extracted_skills)
                    all_jobs.append(job)

        # 5. Sort by match score
        all_jobs.sort(key=lambda x: x.get("match_score", 0), reverse=True)

        return jsonify({
            "extracted_skills": extracted_skills,
            "job_titles":       job_titles,
            "summary":          summary,
            "total":            len(all_jobs),
            "jobs":             all_jobs[:40],
        })

    except Exception as e:
        print(f"Server error: {e}")
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    print(f"\n🚀 Job Matcher API → http://localhost:{port}")
    print(f"   Claude AI : {'✅ enabled' if claude else '⚠️  disabled (local extraction)'}")
    print(f"   RapidAPI  : {'✅ configured' if RAPIDAPI_KEY else '❌ missing key'}\n")
    app.run(host="0.0.0.0", port=port, debug=False)
