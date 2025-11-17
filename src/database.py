import sqlite3
import os

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DB_DIR = os.path.join(BASE_DIR, "db")
DB_PATH = os.path.join(DB_DIR, "index.db")

os.makedirs("db", exist_ok=True)

conn = sqlite3.connect(DB_PATH)
conn.execute("""
CREATE TABLE IF NOT EXISTS works (
    work_id TEXT PRIMARY KEY,
    doi TEXT,
    title TEXT,
    year INTEGER,
    fetched_at TEXT,
    download_attempted BOOLEAN DEFAULT 0,
    primary_pdf_url TEXT,
    best_pdf_url TEXT,
    other_pdf_urls TEXT
)
""")
conn.commit()

conn.execute("""
CREATE TABLE IF NOT EXISTS pdfs (
    work_id TEXT PRIMARY KEY,
    pdf_sha256 TEXT,
    pdf_path TEXT,
    pdf_url_used TEXT,
    downloaded_at TEXT,
    download_error TEXT,
    processed BOOLEAN DEFAULT 0,
    deleted BOOLEAN DEFAULT 0
)
""")

conn.commit()
conn.close()
