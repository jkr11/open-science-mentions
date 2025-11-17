import sqlite3
import os

os.makedirs("db", exist_ok=True)

conn_index = sqlite3.connect("db/index.db")
conn_index.execute("""
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
conn_index.commit()

conn_pdfs = sqlite3.connect("db/pdfs.db")
conn_pdfs.execute("""
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
conn_pdfs.commit()
