FROM ubi9:latest

MAINTAINER JC Lopez and Abhishek Bose version: 0.2 for s390 support

RUN dnf install -y git make gcc unzip wget fio python3
ENV path=$path;/usr/bin

CMD /usr/bin/date;
