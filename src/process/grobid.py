from grobid_client.grobid_client import GrobidClient
from pathlib import Path

config_path = Path.cwd() / "configs" / "grobid_config.json"


class GrobidHandler:
  def __init__(self):
    self.client = GrobidClient(config_path=config_path)

  def process_files(
    self, files: list[str], input_path: str, output_path: str
  ) -> dict[str, str]:
    if self.client is None:
      exit

    _output_path = Path(output_path)
    _output_path.mkdir(parents=True, exist_ok=True)

    # print(files[0])

    try:
      self.client.process_batch(
        service="processFulltextDocument",
        input_files=files,
        output=_output_path,
        n=10,
        json_output=True,
        verbose=True,
        input_path=input_path,
        generateIDs=None,
        consolidate_citations=False,
        include_raw_affiliations=False,
        include_raw_citations=False,
        tei_coordinates=False,
        segment_sentences=False,
        force=True,
        consolidate_header=True,
      )

    except Exception as e:
      print(f"Grobid Exception when processing {input_path}: {e}")

    results: dict[str, str] = {}
    for pdf in files:
      tei_name = Path(pdf).with_suffix(".grobid.tei.xml").name
      tei_path = _output_path / tei_name
      if tei_path.exists() and tei_path.stat().st_size > 0:
        results[pdf] = tei_name
      else:
        print(f"Grobid did not produce output for: {pdf}")
    return results


def init_client(): ...


def process_files(
  files: list[str], input_path: str, output_path: str, client=None
) -> None: ...


def process_dir(input_path: str, output_path: str) -> None:
  client = GrobidClient(config_path=config_path)
  try:
    client.process(
      service="processFulltextDocument",
      input_path=input_path,
      output=output_path,
      n=10,
      json_output=True,
      verbose=True,
    )
  except Exception as e:
    print(f"Grobid Exception when processing {input_dir}: {e}")


if __name__ == "__main__":
  print("[*] TEST RUNNING FOR GROBID.py")
  input_dir = "testdata/pdfs"
  output_dir = "testdata/teis"
  process_dir(input_path=input_dir, output_path=output_dir)
