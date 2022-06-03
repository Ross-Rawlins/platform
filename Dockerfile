FROM openhie/package-base:0.1.0

ADD . .

# Install yq
RUN curl -L https://github.com/mikefarah/yq/releases/download/v4.23.1/yq_linux_amd64 -o /usr/bin/yq
RUN chmod +x /usr/bin/yq

# Install jq

RUN apt install jq -y &>/dev/null
