FROM 894939414795.dkr.ecr.eu-west-1.amazonaws.com/docker-infra:v1.18.0

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]