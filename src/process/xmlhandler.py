from lxml import etree
import grobid_tei_xml as gtx
import json

class XMLHandler:
  def extract_abstract(self):
    pass

  @classmethod
  def extract_fulltext(self, xmlpath) -> str:
    with open(xmlpath, "r") as xmlfile:
      doc = gtx.parse_document_xml(xmlfile.read())
      return json.dumps(doc.to_dict())

  def extract_data_availibility_statement(self, xmlpath) -> str | None:
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

  def extract_body_text(self) -> str | None:
    pass
