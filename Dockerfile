FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
  curl xz-utils libreadline-dev valgrind build-essential python3 \
  && rm -rf /var/lib/apt/lists/*

RUN curl -L "https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz" | tar -xJ -C /usr/local/bin --strip-components=1

WORKDIR /app 

COPY . .

RUN chmod +x integration_tests.sh

CMD [ "./integration_tests.sh" ]
