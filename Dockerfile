FROM debian:9-slim
RUN apt-get update \
  && apt-get install -y wget
