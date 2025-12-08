import sqlite3
import os

TEST = True  # Set to false for actual run

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if TEST:
  DB_DIR = os.path.join(BASE_DIR, "test_db")
else:
  DB_DIR = os.path.join(BASE_DIR, "db")
  DB_PATH = os.path.join(DB_DIR, "index.db")

DOWNLOAD_DIR_PDFS = os.path.join(DB_DIR, "pdfs")
DOWNLOAD_DIR_TEIS = os.path.join(DB_DIR, "teis")


os.makedirs(DB_DIR, exist_ok=True)


def mktable():
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


def setup_pipeline_table():
  try:
    with sqlite3.connect(DB_PATH) as conn:
      cursor = conn.cursor()
      cursor.execute("""
        CREATE TABLE IF NOT EXISTS works (
        openalex_id TEXT PRIMARY KEY,
        journal_id TEXT,
        journal_name TEXT,
        doi TEXT,
        publication_year INTEGER,
        oa_urls TEXT,
        pdf_download_status TEXT DEFAULT 'PENDING', -- PENDING, SUCCESS, FAILED
        pdf_local_path TEXT,
        tei_process_status TEXT DEFAULT 'PENDING',
        tei_local_path TEXT,
        );
      """)
      conn.commit()
      print(f"Database '{DB_PATH}' initialized successfully.")
  except sqlite3.Error as e:
    print(f"An error occured during database setup: {e}")


# def setup_pdf_table():
#   conn.execute("""
#   CREATE TABLE IF NOT EXISTS pdfs (
#       work_id TEXT PRIMARY KEY,
#       pdf_sha256 TEXT,
#       pdf_path TEXT,
#       pdf_url_used TEXT,
#       downloaded_at TEXT,
#       download_error TEXT,
#       processed BOOLEAN DEFAULT 0,
#       deleted BOOLEAN DEFAULT 0
#   )
#   """)

if __name__ == "__main__":
  setup_pipeline_table()