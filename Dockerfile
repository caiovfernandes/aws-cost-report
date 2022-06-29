FROM dnxsolutions/aws-v2:2.4.29-dnx1

COPY . /root/aws-cost-report
WORKDIR /root/aws-cost-report

RUN apk add --update --no-cache python3 && ln -sf python3 /usr/bin/python && python3 -m ensurepip && pip3 install --no-cache-dir  --upgrade -r ./requirements.txt
RUN apk add jq
RUN apk add curl

ENV PYTHONUNBUFFERED=0

ENTRYPOINT ["/root/aws-cost-report/run.py"]
