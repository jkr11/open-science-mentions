import uvicorn
from fastapi import FastAPI, HTTPException
from process.analysis import FrontiersHandler
from typing import Optional, Dict, Any

app = FastAPI()


@app.get("/process")
def process_data(path: str) -> Dict[str, Any]:
  try:
    fh = FrontiersHandler(path)
    das = fh.extract_das()
    res: Optional[int] = fh.analyze_das(das)

    return {"result": res, "status": "success"}

  except Exception as e:
    raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
  uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=True)
