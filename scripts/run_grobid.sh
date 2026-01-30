docker inspect grobid/grobid:0.8.2.1-full > /dev/null 2>&1 || docker pull grobid/grobid:0.8.2.1-full && \
docker run --rm --init --ulimit core=0 -p 8070:8070 grobid/grobid:0.8.2.1-full    
