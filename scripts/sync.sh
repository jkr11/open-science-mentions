#!/bin/bash

rsync -av --delete /home/jere/projects/open_science_mentions/db/ /mnt/NetworkDrive/current/

rsync -av --delete /home/jere/projects/open_science_mentions/db/ /mnt/NetworkDrive/current/db/

find /mnt/NetworkDrive/archive/* -type d -ctime +30 -exec rm -rf {} +