import subprocess
import random
import time


SERVER_POOL = [("us", "nyc"), ("de", "fra"), ("se", "sto"), ("nl", "ams")]
# only ("de", "dus") works for sage, so reserve it for that.
# TODO: add more vpn options like nord


def rotate_vpn_server() -> None:
  """
  Rotates Mullvad VPN

  Moves the vpn node to one of the locations given in SERVER_POOL.
  - SERVER_POOL = [("us", "nyc"), ("de", "fra"), ("se", "sto"), ("nl", "ams"), ...]
  """
  try:
    country, city = random.choice(SERVER_POOL)
    print(f"--- Attempting rotation to new server: {country} {city} ---")
    subprocess.run(["mullvad", "disconnect"], capture_output=True, text=True)

    subprocess.run(
      ["mullvad", "relay", "set", "location", country, city],
      check=True,
      capture_output=True,
      text=True,
    )

    subprocess.run(["mullvad", "connect"], capture_output=True, text=True)

    subprocess.run(
      ["mullvad", "connect"],
      check=True,
      capture_output=True,
      text=True,
    )
    time.sleep(1)  # TODO check, for now it is always enough

    status_check = subprocess.run(
      ["mullvad", "status"], check=True, capture_output=True, text=True
    ).stdout
    print(status_check)
    print("-" * 50)
  except subprocess.CalledProcessError as e:
    print("\n Subprocess ERROR during rotation")
    print(f"Command failed: {e.cmd}")
    print(f"Return code: {e.returncode}")
    print(f"Error output (stderr):\n{e.stderr.strip()}")
    print("-" * 50)