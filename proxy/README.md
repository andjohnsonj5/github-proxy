Simple FastAPI reverse proxy to https://github.com

Usage (local):

- Install deps: `pip install -r requirements.txt`
- Run: `uvicorn main:app --host 0.0.0.0 --port 8000`
- Clone via proxy: `git clone http://127.0.0.1:8000/octocat/Hello-World.git`

Docker:

- Build: `docker build -t fastapi-github-proxy .`
- Run: `docker run -p 8000:8000 fastapi-github-proxy`
- Then clone as above against `http://localhost:8000/...`

