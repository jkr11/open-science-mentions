#!/usr/bin/env python3
import csv
import argparse


def main():
  parser = argparse.ArgumentParser(description="Convert CSV to a LaTeX table.")
  parser.add_argument("input_csv", help="Input CSV file")
  parser.add_argument("-c", "--caption", help="Caption", default="")
  parser.add_argument("-o", "--output", help="Output .tex file (default: stdout)")
  parser.add_argument("-s", "--sep", help="Delimiter in [; ,] (default: ;)", default=";")
  args = parser.parse_args()


  with open(args.input_csv, newline="", encoding="utf-8") as f:
    rows = list(csv.reader(f, delimiter=args.sep))

  header = rows[0]  # Assume this exists, maybe do this by heuristic
  body = rows[1:]
  n = len(header)

  col_format = "|" + "|".join(["l"] * n) + "|"
  lines = []
  lines.append(r"\begin{table}[h]")
  lines.append(r"\centering")
  lines.append(r"\caption{" + args.caption + "}")
  lines.append(r"\begin{tabular}{" + col_format + "}")
  lines.append(r"\hline")
  lines.append(" & ".join(header) + r" \\ \hline")

  for row in body:
    if row:
      lines.append(" & ".join(row) + r" \\ \hline")

  lines.append(r"\end{tabular}")
  lines.append(r"\end{table}")

  output = "\n".join(lines)

  if args.output:
    with open(args.output, "w", encoding="utf-8") as f:
      f.write(output)
  else:
    print(output)


if __name__ == "__main__":
  main()
