import sqlite3
import os
import json
from database import DB_PATH, DB_DIR
from process.download import PDFDownloader
from process.grobid import process_dir
from process.analysis import FrontiersHandler
import asyncio
import pandas as pd


# LIMIT = 100
# print(f"Does file exist? {os.path.exists(DB_PATH)}")
#
# extracted_links = []
# with sqlite3.connect(DB_PATH) as conn:
#  cursor = conn.cursor()
#  cursor.execute(f"SELECT openalex_id, oa_urls FROM works WHERE oa_urls IS NOT NULL AND oa_urls != '' LIMIT {LIMIT}")
#  results = cursor.fetchall()
#  for row in results:
#    openalex_id = row[0]
#    json_str = row[1]
#    oa_data = json.loads(json_str)
#    extracted_links.extend(oa_data['pdf_links'])
#
# print(extracted_links[:10])
#
# DOWNLOAD_DIR_PDF = os.path.join(DB_DIR, "pdfs")
# DOWNLOAD_DIR_TEI = os.path.join(DB_DIR, "teis")
#
# async def run_example():
#  downloader = PDFDownloader(DOWNLOAD_DIR_PDF, switch_time=600)
#  async with downloader:
#    try:
#      await downloader.run_batch(extracted_links[10:20])
#      print("All complete")
#    except Exception as e:
#      print(f"Error during batch download: {e}")
#    finally:
#      print("Exited")
#
# def dir_iterator(input_dir, ext):
#  for file in os.listdir(input_dir):
#    if file.split(".")[-1] == ext:
#      yield file


def is_in_dir(name, path="test_db/pdfs"):
  for file in os.listdir(path):
    if name in file:
      print(name)
      return True
  return False


def build_test_set(LIMIT=200):
  df = pd.DataFrame()
  true_rows = []
  with sqlite3.connect(DB_PATH) as conn:
    cursor = conn.cursor()
    cursor.execute(
      f"SELECT openalex_id, pdf_local_path FROM works WHERE pdf_download_status='DONE' LIMIT {LIMIT}"
    )
    rows = cursor.fetchall()
    for row in rows:
      if is_in_dir(row[1].split("/")[-1]):
        true_rows.append(row)

    df = pd.DataFrame(true_rows, columns=["openalex_id", "pdf_local_path"])

    df["filename"] = df["pdf_local_path"].apply(lambda path: path.split("/")[-1])
    df = df.sort_values(by="filename")

    df.to_csv("experiment/test_set.csv", index=False)


if __name__ == "__main__":
  # build_test_set()
  df = pd.read_csv("experiment/test_set_ground_truth.csv")

# asyncio.run(run_example())
# process_dir(DOWNLOAD_DIR_PDF, DOWNLOAD_DIR_TEI)
# for i in dir_iterator(DOWNLOAD_DIR_TEI, "xml"):
#   fh = FrontiersHandler(os.path.join(DOWNLOAD_DIR_TEI, i))
#   print(fh.has_data())
#   print(fh.get_availibility_score())
