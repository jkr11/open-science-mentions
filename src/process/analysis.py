from lxml import etree
from rapidfuzz import fuzz, process
import re
import requests

FrontiersMatch = {
  "Original datasets are available in a publically accessible repository": 6,
  "Publicly available datasets were analyzed in this study": 5,
  "The datasets presented in this study can be found in online repositories": 4,
  "The original contributions presented in the study are included in the article/supplementary material": 3,
  "The datasets presented in this article are not readily available because": 2,
  "The data analyzed in this study was obtained from": 1,
  "The raw data supporting the conclusions of this article will be made available by the authors, without undue reservation": 0,
}

class OSFHandler:
  @classmethod
  def get_files(cls, _url):
    url = f"{_url}/files/"
    print(url)
    resp = requests.get(url)
    data = resp.json()
    for file_enty in data["data"]:
      print(file_enty["attributes"]["name"])

def extract_github_links(text) -> str:
  github_regex = "(?:https?://)?github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*"
  pattern = re.compile(
    fr"{github_regex}",
    re.IGNORECASE,
  )
  raw_links = pattern.findall(text)
  return raw_links

def extract_links_regex(text) -> str:
  url_pattern = re.compile(
    r"((?:https?://)?(?:www\.)?(?:github\.com|osf\.io|example\.com)[^\s]*(?:\s[^\s]+)*)",
    re.IGNORECASE,
  )

  raw_links = url_pattern.findall(text)

  cleaned_links = []
  for link in raw_links:
    link = link.replace(" ", "")
    if not link.startswith("http"):
      link = "https://" + link
    cleaned_links.append(link)

  return cleaned_links


class FrontiersHandler:
  def __init__(self, input_path):
    self.input_path = input_path

  def get_availibility_score(self):
    das = self.extract_das(self.input_path)
    if das:
      return self.analyze_das(das)
    return None

  def has_data(self):
    return self.extract_das(self.input_path) is not None

  def extract_das(self, xmlpath=None):
    if xmlpath is None:
      xmlpath = self.input_path
    try:
      tree = etree.parse(xmlpath)
      root = tree.getroot()
      ns = {"tei": "http://www.tei-c.org/ns/1.0"}

      availability_div = root.find(".//tei:div[@type='availability']", namespaces=ns)

      if availability_div is not None:
        return " ".join(availability_div.itertext()).strip()
      else:
        return None
    except Exception as e:
      print(f"Error extracting data: {e}")
      return None

  def analyze_das(self, text):
    print("Analyzing: ", text)
    if not text:
      return None

    choices = list(FrontiersMatch.keys())
    match = process.extractOne(text, choices, scorer=fuzz.partial_ratio)

    if match:
      matched_choice, score, _ = match
      # print(f"Score: {score}")
      # print(f"Label: {FrontiersMatch[matched_choice]}")
      return FrontiersMatch[matched_choice]
    return None
