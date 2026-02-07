import requests
from database import DB_DIR
from dotenv import load_dotenv
from typing import List, Generator, Any
import os

env = load_dotenv()

EMAIL_ADRESS = os.getenv("EMAIL_ADRESS") or "ui@openalex.org"

OPEN_ALEX_API_URL = "https://api.openalex.org/works"

INDEX_DB = os.path.join(DB_DIR, "openalex_jsonl")


def get_journal_by_id(
  journal_ids: List[str], per_page: int, min_year: int, pdf:bool=True, _cursor=None
) -> Generator[Any, None, None]:
  """
  Docstring for get_journal_by_id
  
  :param journal_ids: Journal ids given in the openalex-format. For example "S2596526815" for Frontiers in education.
  :type journal_ids: List[str]
  :param per_page: the amount of works fetched per page, i.e. batch size.
  :type per_page: int
  :param min_year: For example 2016, only works with publication_year > min_year are fetched
  :type min_year: int
  :param pdf: if this is True, only openalex works endowed with an open access pdf link are fetched, note that openalex does not necessarily find all pdfs, for example PeDocs is not accessible.
  :type pdf: bool
  :return: 
  :rtype: Generator[Any, None, None]
  """
  cursor = "*" if not _cursor else _cursor
  if isinstance(journal_ids, str):
    journal_ids = [journal_ids]
  while True:
    params = {
      "cursor": cursor,
      "per_page": per_page,
      "filter": (
        "primary_location.source.id:"
        f"{'|'.join(journal_ids)}"
        ",open_access.is_oa:true"
        f",has_content.pdf:{pdf}"
        f",publication_year:>{min_year}"
        ",type:article"
      ),
      "sort": "publication_year:desc",
      "mailto": f"{EMAIL_ADRESS}",
    }
    print(f"Query: {params}")
    try:
      r = requests.get(OPEN_ALEX_API_URL, params=params, timeout=100)
      r.raise_for_status()
      payload = r.json()
    except requests.exceptions.RequestException as e:
      print(f"An API request error occured: {e}")
      print(f"With cursor: {cursor}")
      break

    results = payload.get("results", [])
    if not results:
      print("INFO: No more results found on this page. Stopping.")
      break

    for w in results:
      yield w

    cursor = payload.get("meta", {}).get("next_cursor")
    if not cursor:
      print("No more works to fetch, stopping fetch.")
      break


def extract_pdf_locations(work: dict) -> dict[str, list[Any]]:
  """
  Concatenates all possible pdf locations if available.
  
  :param work: Description
  :type work: an openalex object
  :return: A json object of a list of pdf links
  :rtype: dict[str, list[Any]]
  """
  primary = work.get("primary_location", {}).get("pdf_url")
  best = work.get("best_oa_location", {}).get("pdf_url")
  others = work.get("locations", [])
  other_urls = [loc.get("pdf_url") for loc in others if loc.get("pdf_url")]
  pdf_links = [best] + [primary] + other_urls
  return {"pdf_links": list(set(pdf_links))}

def get_github_files(owner, repo, path=""):
    url = f"https://api.github.com/repos/{owner}/{repo}/contents/{path}"
    response = requests.get(url)
    
    if response.status_code == 200:
        contents = response.json()
        for item in contents:
            print(f"{item['type'].upper()}: {item['name']}")
    else:
        print(f"Error: {response.status_code}")

def get_all_files_recursive(owner, repo, branch="main"):
    url = f"https://api.github.com/repos/{owner}/{repo}/git/trees/{branch}?recursive=1"
    response = requests.get(url)
    
    if response.status_code == 200:
        tree = response.json().get("tree", [])
        for item in tree:
            type_label = "FILE" if item["type"] == "blob" else "DIR "
            print(f"{type_label}: {item['path']}")
    else:
        print(f"Failed to fetch: {response.status_code}")

def github_to_api(github_link : str) -> tuple[str, str]:
  parts = github_link.split("/")
  print(parts)
  user = parts[3]
  name = parts[4]
  print(f"User:_{user}, {name}")
  return (user, name)