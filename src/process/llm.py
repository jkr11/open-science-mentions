import requests
import json

API_PORT = "11434"

ollama_url = f"http://127.0.0.1:{API_PORT}/api/generate"

models = ["llama3:8b", "llama3.2:1b"]


def is_article_data_based(msg: str, model_name: str = "llama3:8b"):
  url = ollama_url

  system_prompt = (
    "You are an expert academic text analyzer. Your taks is to decide based on either an abstract or an excerpt of a paper"
    "whether the journal is not data based (a review article or a general method) or if it is data based."
    "Your response must be one of the following letters:"
    "\n 'R': for review article"
    "\n 'M': for method"
    "\n 'D': for data"
  )

  payload = {
    "model": model_name,
    "prompt": f"--- STATEMENT ---\n{msg}\n\nCLASSIFICATION CODE:",
    "system": system_prompt,
    "stream": False,
    "options": {
      "num_thread": 16,
      "temperature": 0.0,
      "keep_alive": -1,
      "num_predict": 20,
    },
  }

  try:
    response = requests.post(url, json=payload)
    response.raise_for_status()
    return response.text
  except Exception as e:
    print(f"Exception when deciding: {e}")


def get_das_classification(msg: str, model_name: str = "llama3:8b"):
  url = ollama_url

  system_prompt = (
    "You are an expert academic text analyzer. Your task is to classify the intent of the provided Data Availability Statement (DAS)."
    "You are a mandatory classification bot. Analyze the Data Availability Statement (DAS) and "
    "classify it into one of three codes: A (Available), R (Restricted/Request), or N (Not Applicable/No Data). "
    'Your response MUST be a single JSON object adhering to this schema: {"code": "[A or R or N]"}.'
    "\nA: Data is openly available and includes a link, repository name or accession code."
    "\nR: Data is available upon reasonable request, restricted, or subject to proprietary access."
    "\nN: Data is not applicable or was not generated for this study (e.g., a review paper)."
  )

  payload = {
    "model": model_name,
    "prompt": f"--- STATEMENT ---\n{msg}\n\nCLASSIFICATION CODE:",
    "system": system_prompt,
    "stream": False,
    "format": "json",
    "options": {
      "num_thread": 16,
      "temperature": 0.0,
      "keep_alive": -1,
      "num_predict": 20,
    },
  }

  try:
    response = requests.post(url, json=payload)
    response.raise_for_status()

    full_response = response.json().get("response", "").strip()
    try:
      json_data = json.loads(full_response)

      classification = json_data.get("code", "ERROR").strip().upper()
    except json.JSONDecodeError:
      classification = f"PARSE_ERROR: {full_response}"

    return classification
  except requests.exceptions.RequestException as e:
    print(f"Error communicating with Ollama: {e}")
    return "ERROR"


if __name__ == "__main__":
  statements_to_check = [
    "The data and code supporting the findings of this study are available on GitHub at https://github.com/data/project-das.",
    "Data are available from the corresponding author upon reasonable request.",
    "This is a review article and did not generate any new data.",
  ]

  print(
    f"--- Classifying Statements using {models[1]} (Threads: {32}, Keep-Alive: {-1}) ---"
  )

  for i, statement in enumerate(statements_to_check):
    print(f"\n--- Statement {i + 1} ---")
    print(f'Input: "{statement}"')

    result = get_das_classification(statement)
    print(result)
