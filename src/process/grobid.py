from grobid_client.grobid_client import GrobidClient
from pathlib import Path

GROBID_FULL_URL = "http://localhost:8070"  # Usually localhost:8070 TODO settings

config_path = Path.cwd() / "configs" / "grobid_config.json"


def process_dir(input_path: str, output_path: str) -> None:
  client = GrobidClient(config_path=config_path)
  try:
    client.process(
      service="processFulltextDocument",
      input_path=input_path,
      output=output_path,
      n=20,
      json_output=True,
    )
  except Exception as e:
    print(f"Grobid Exception when processing {input_dir}: {e}")


if __name__ == "__main__":
  print("[*] TEST RUNNING FOR GROBID.py")
  input_dir = "testdata/pdfs"
  output_dir = "testdata/teis"
  process_dir(input_path=input_dir, output_path=output_dir)
