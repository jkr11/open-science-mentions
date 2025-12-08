import requests
from typing import List,Tuple
from grobid_client.grobid_client import GrobidClient
import numpy as np
client = GrobidClient()

def extract_grobid(pdf_path: str, grobid_url: str = "http://localhost:8070") -> None | str:
  with open(pdf_path, "rb") as f:
    files = {"input": f}
    try:
      resp = requests.post(grobid_url, files=files, timeout=60)
    except Exception as e:
      print(f"GROBID request failed: {e}")
      return None
    if resp.status_code != 200:
      print(f"GROBID error {resp.status_code}")
      return None

    tei_xml = resp.text
    return tei_xml

def search_keywords_naive(text : str, keywords : List[str]) -> Tuple[List[str], str]:
  text_lower = text.lower()
  matched = []
  for kw in keywords:
    if kw in text_lower:
      matched.append(kw)
  return matched, ""

FrontiersMatch = {
  "Original datasets are available in a publically accessible repository" : 6,
  "Publicly available datasets were analyzed in this study" : 5,
  "The datasets presented in this study can be found in online repositories" : 4,
  "The original contributions presented in the study are included in the article/supplementary material" : 3,
  "The datasets presented in this article are not readily available because" : 2,
  "The data analyzed in this study was obtained from" : 1,
  "The raw data supporting the conclusions of this article will be made available by the authors, without undue reservation" : 0
}

class FrontiersHandler:
  @classmethod
  def extract_das(self, xmlpath):
    from lxml import etree

    tree = etree.parse(xmlpath)
    root = tree.getroot()
    ns = {"tei": "http://www.tei-c.org/ns/1.0"}

    availability_div = root.find(".//tei:div[@type='availability']", namespaces=ns)

    if availability_div is not None:
      text_content = " ".join(availability_div.itertext()).strip()
      # print(text_content)
      return text_content
    else:
      print("No availability div found.")
  
  @classmethod
  def analyze_das(self, text):
    from rapidfuzz import fuzz, process
    choices = list(FrontiersMatch.keys())

    res = process.extractOne(text, choices, scorer=fuzz.partial_ratio)
    if res is not None:
      match, score, idx = res 
  
      print("Score:", score)
      print("Label:", FrontiersMatch[match])
      label = FrontiersMatch[match]
      return label
    return None
  


Keywords = ["Open Science", "open science", "Data availability statement", "Data will be published", "available", "open source", "source code", "github", "github.com", "code.google.com"]

def search(filename : str):
  with open(filename, "rb") as f:
    text = f.read()
    return search_keywords_naive(str(text), keywords=Keywords)

def main_grobid():
  client.process(service="processFulltextDocument", input_path="./pdfs", output="./results", n=1)
  print(search("./results/458.grobid.tei.xml"))


if __name__ == "__main__":
  import os
  dirname = "data/teis"
  labels = []
  for filename in os.listdir(dirname):
    if filename.endswith(".xml"):
      text = FrontiersHandler.extract_das("data/teis/"+ str(filename))
      label = FrontiersHandler.analyze_das(text)
      if label is not None:
        labels.append(label)

  print(np.mean(labels))
  

  text =FrontiersHandler.extract_das("./data/teis/sha256_0befb1f9be2db8f540610873029568d3370126e66d15145dd69340c1075387cb.grobid.tei.xml")
  FrontiersHandler.analyze_das(text)