"""
Setup the tables used in the pipline. We should outsource most of this to (pydantic?) settings.
"""

import sqlite3
import os


TEST = True

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if TEST:
  DB_DIR = os.path.join(BASE_DIR, "test_db")
else:
  DB_DIR = os.path.join(BASE_DIR, "db")

DB_PATH = os.path.join(DB_DIR, "index.db")

DOWNLOAD_DIR_PDFS = os.path.join(DB_DIR, "pdfs")
DOWNLOAD_DIR_TEIS = os.path.join(DB_DIR, "teis")


os.makedirs(DB_DIR, exist_ok=True)


def empty_table():
  try:
    with sqlite3.connect(DB_PATH) as conn:
      cursor = conn.cursor()
      cursor.execute("""
          DELETE FROM works    
        """)
      conn.commit()
      print(f"Database: '{DB_PATH}' emptied successfully.")
  except Exception as e:
    print(f"An error occured when emptying the table: {e}")


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
        tei_local_path TEXT
        );
      """)
      conn.commit()
      print(f"Database '{DB_PATH}' initialized successfully.")
  except sqlite3.Error as e:
    print(f"An error occured during database setup: {e}")


TO_TEI_QUERY = """ UPDATE works 
SET tei_process_status = ?, tei_local_path = ? 
WHERE openalex_id = ?; """

if __name__ == "__main__":
  #empty_table()
  setup_pipeline_table()
